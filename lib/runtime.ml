open Effect.Shallow

type _epoll_manager = { epfd : Unix.file_descr; managed : (Unix.file_descr, _some_managed_fd) Hashtbl.t }
and 'a _managed_fd = { manager : _epoll_manager; fd : Unix.file_descr; mutable awaiters : (unit, unit) continuation list }
  constraint 'a = [< `R | `W ]
and _some_managed_fd = SomeManagedFd : [< `R | `W ] _managed_fd -> _some_managed_fd

type ctx = {
  sched : 'a. ('a, unit) continuation -> 'a -> unit;
  ep : _epoll_manager;
  queued_tasks : unit -> int;
  live_tasks : int ref;
}

type _ eff += WithCont : (('a, unit) continuation -> unit) -> 'a eff | Ctx : ctx eff

let get_ctx () = Effect.perform Ctx

module Promise = struct
  type 'a promise_state = Resolved of 'a | Unresolved of ('a, unit) continuation list
  type 'a t = 'a promise_state ref

  let create () = ref (Unresolved [])
  let await p =
    match !p with
    | Resolved x -> x
    | Unresolved xs -> Effect.perform (WithCont (fun k -> p := Unresolved (k :: xs)))
  let resolve p x =
    match !p with
    | Resolved x' -> failwith "Cannot resolve already-resolved promise"
    | Unresolved xs ->
      let ctx = get_ctx () in
      p := Resolved x;
      List.iter (fun k -> ctx.sched k x) xs
end

type 'a promise = 'a Promise.t

module Epoll = struct
  (* We specifically only support read for now *)

  type fd = Unix.file_descr

  type t = _epoll_manager = { epfd : fd; managed : (fd, some_managed_fd) Hashtbl.t }
  and 'a managed_fd = 'a _managed_fd = { manager : t; fd : fd; mutable awaiters : (unit, unit) continuation list }
    constraint 'a = [< `R | `W ]
  and some_managed_fd = _some_managed_fd = SomeManagedFd : [< `R | `W ] managed_fd -> some_managed_fd

  external epoll_create : unit -> fd = "ocaml_epoll_create"
  external epoll_register : fd -> int -> fd -> unit = "ocaml_epoll_register"
  (* timeout=-1 means no timeout, res=-1 means no events *)
  external epoll_wait_one : fd -> int -> int = "ocaml_epoll_wait_one"

  let create () =
    let epfd = epoll_create () in
    { epfd; managed = Hashtbl.create 0 }

  let register_read manager fd : [ `R ] managed_fd =
    epoll_register manager.epfd 1 fd;
    Unix.set_nonblock fd;
    let res = { manager; fd; awaiters = [] } in
    Hashtbl.add manager.managed fd (SomeManagedFd res);
    res

  let register_write manager fd : [ `W ] managed_fd =
    epoll_register manager.epfd 2 fd;
    Unix.set_nonblock fd;
    let res = { manager; fd; awaiters = [] } in
    Hashtbl.add manager.managed fd (SomeManagedFd res);
    res

  let register_readwrite manager fd : [ `R | `W ] managed_fd =
    epoll_register manager.epfd 3 fd;
    Unix.set_nonblock fd;
    let res = { manager; fd; awaiters = [] } in
    Hashtbl.add manager.managed fd (SomeManagedFd res);
    res

  let stdin = lazy (register_read (get_ctx ()).ep Unix.stdin)
  let stdout = lazy (register_write (get_ctx ()).ep Unix.stdout)

  let rec read ~fd ~buf ~count =
    match Unix.read fd.fd buf 0 count with
    | n -> n
    | exception Unix.Unix_error (Unix.EAGAIN, _, _) ->
      Effect.perform (WithCont (fun k -> fd.awaiters <- k :: fd.awaiters));
      read ~fd ~buf ~count

  let rec write ~fd ~buf ~count =
    match Unix.write fd.fd buf 0 count with
    | n -> n
    | exception Unix.Unix_error (Unix.EAGAIN, _, _) ->
      Effect.perform (WithCont (fun k -> fd.awaiters <- k :: fd.awaiters));
      write ~fd ~buf ~count

  let task ctx =
    while !(ctx.live_tasks) > 1 do
      let timeout = if ctx.queued_tasks () = 0 then -1 else 0 in
      match epoll_wait_one ctx.ep.epfd timeout with
      | -1 -> Effect.perform (WithCont (fun k -> ctx.sched k ()))
      | fd ->
        let fd : fd = Obj.magic fd in
        let SomeManagedFd managed = Hashtbl.find ctx.ep.managed fd in
        let awaiters = managed.awaiters in
        managed.awaiters <- [];
        List.iter (fun k -> ctx.sched k ()) awaiters
    done
end

module Timer = struct
  type t = [ `R ] Epoll.managed_fd

  external timerfd_create : unit -> Epoll.fd = "ocaml_timerfd_create"
  external timerfd_settime : Epoll.fd -> int -> int -> unit = "ocaml_timerfd_settime"

  let create interval =
    let ctx = get_ctx () in
    let fd = timerfd_create () in

    let (fr, secs) = Float.modf interval in
    let secs = Int.of_float secs
    and nanosecs = Int.of_float (1e9 *. fr) in
    timerfd_settime fd secs nanosecs;

    Epoll.register_read ctx.ep fd

  let wait timer =
    let buf = Bytes.create 8 in
    let _ = Epoll.read ~fd:timer ~buf ~count:8 in
    ()
end

type job = MkJob : 'a * ('a, unit) continuation -> job

let run (f : unit -> unit) : unit =
  let queue = Queue.create () in
  let ep = Epoll.create () in
  let queued_tasks () = Queue.length queue in
  let live_tasks = ref 0 in

  let sched k x = Queue.push (MkJob (x, k)) queue in
  let ctx = { sched; ep; live_tasks; queued_tasks } in

  let rec effc : type e. e eff -> ((e, unit) continuation -> unit) option = function
  | WithCont f -> Some (fun k -> f k)
  | Ctx -> Some (fun k -> continue_with k ctx handler)
  | _ -> None
  and handler = { retc = (fun () -> decr live_tasks); exnc = raise; effc } in

  let rec go () =
    match Queue.take_opt queue with
    | Some (MkJob (x, k)) -> continue_with k x handler; go ()
    | None -> ()
  in

  let epoll_task = fiber (fun () -> Epoll.task ctx) in
  sched epoll_task (); incr live_tasks;
  sched (fiber f) (); incr live_tasks;
  go ()

let spawn_u_ctx ctx f = incr ctx.live_tasks; ctx.sched (fiber f)
let spawn_ctx ctx f x =
  let p = Promise.create () in
  spawn_u_ctx ctx (fun x -> Promise.resolve p (f x)) x;
  p

let spawn_u f = spawn_u_ctx (get_ctx ()) f
let spawn f = spawn_ctx (get_ctx ()) f

let yield () = let ctx = get_ctx () in Effect.perform (WithCont (fun k -> ctx.sched k ()))

module Prelude = struct
  module Promise = Promise
  type nonrec 'a promise = 'a promise

  module Epoll = Epoll

  let spawn = spawn
  let yield = yield
  let await = Promise.await
end
