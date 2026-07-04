(** Promises *)
module Promise : sig
  (** A promise that may be resolved with a ['a] *)
  type !'a t

  (** Creates a new, unresolved promise *)
  val create : unit -> 'a t

  (** Suspends execution until the promise is resolved *)
  val await : 'a t -> 'a

  (** Resolves the promise. If the promise has already been resolved, fails *)
  val resolve : 'a t -> 'a -> unit
end

(** A promise that may be resolved with a ['a] *)
type 'a promise = 'a Promise.t

(** Runs the function concurrently, storing its result in a promise *)
val spawn : ('a -> 'b) -> ('a -> 'b promise)

(** Runs the function concurrently *)
val spawn_u : ('a -> unit) -> 'a -> unit

(** Entry point to the runtime *)
val run : (unit -> unit) -> unit

(** Lets other pending tasks run *)
val yield : unit -> unit

module Epoll : sig
  (** A Unix file descriptor *)
  type fd = Unix.file_descr

  (** An epollfd "manager" *)
  type t

  (** A managed fd. ['a] is an extensible variant type denoting which operations are allowed *)
  type 'a managed_fd constraint 'a = [< `R | `W ]

  (** A managed fd *)
  type some_managed_fd = SomeManagedFd : [< `R | `W ] managed_fd -> some_managed_fd

  (** Registers the given fd with the epoll manager and sets it to nonblocking mode *)
  val register_read : t -> fd -> [ `R ] managed_fd

  (** Registers the given fd with the epoll manager and sets it to nonblocking mode *)
  val register_write : t -> fd -> [ `W ] managed_fd

  (** Registers the given fd with the epoll manager and sets it to nonblocking mode *)
  val register_readwrite : t -> fd -> [ `R | `W ] managed_fd

  (** Reads up to [count] bytes into [buf] asynchronously *)
  val read : fd:[> `R ] managed_fd -> buf:bytes -> count:int -> int

  (** Writes up to [count] bytes from [buf] asynchronously *)
  val write : fd:[> `W ] managed_fd -> buf:bytes -> count:int -> int

  val stdin : [ `R ] managed_fd Lazy.t
  val stdout : [ `W ] managed_fd Lazy.t
end

(** Contains useful things *)
type ctx = {
  sched : 'a. ('a, unit) Effect.Shallow.continuation -> 'a -> unit;
  ep : Epoll.t;
  queued_tasks : unit -> int; (** Returns number of queued tasks *)
  live_tasks : int ref; (** Incremented on task creation (spawn), decremented in retc *)
}

val get_ctx : unit -> ctx

(** Timers *)
module Timer : sig
  (** A timer *)
  type t

  (** Creates a timer that creates an event every n seconds *)
  val create : float -> t

  (** Waits for the timer to tick *)
  val wait : t -> unit
end

module Prelude : sig
  module Promise = Promise
  type nonrec 'a promise = 'a promise

  module Epoll = Epoll

  val yield : unit -> unit
  val await : 'a promise -> 'a
  val spawn : ('a -> 'b) -> ('a -> 'b promise)
end
