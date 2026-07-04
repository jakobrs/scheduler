open Scheduler

let server () =
  let open Runtime.Prelude in
  let module Tcp = Runtime.Tcp in
  let listener = Tcp.listen ~addr:(Unix.inet_addr_of_string "127.0.0.1") ~port:8080 in
  while true do
    let client, addr = Tcp.accept listener in
    Runtime.spawn_u begin fun () ->
      let buf = Bytes.create 1024 in
      while true do
        let n = Epoll.read ~fd:client ~buf ~count:1024 in
        Epoll.write_all ~fd:client ~buf ~from:0 ~count:n
      done
    end ()
  done

let f () =
  let open Runtime.Prelude in
  let module Timer = Runtime.Timer in

  Runtime.spawn_u server ();

  let stdin = Lazy.force Epoll.stdin in
  let buf = Bytes.create 20 in
  let n = Epoll.read ~fd:stdin ~buf ~count:10 in
  Printf.printf "Read %d bytes\n%!" n;

  Runtime.spawn_u begin fun () ->
    let stdout = Lazy.force Epoll.stdout in
    while true do
      let n = Epoll.read ~fd:stdin ~buf ~count:20 in
      ignore @@ Epoll.write ~fd:stdout ~buf ~from:0 ~count:n
    done
  end ();

  let timer_job id interval : unit =
    let timer = Timer.create interval in
    for i = 1 to 20 do
      Timer.wait timer;
      Printf.printf "%d %!" id
    done
  in
  let a = spawn (fun () -> timer_job 0 (1. /. 3.)) ()
  and b = spawn (fun () -> timer_job 1 (1. /. 4.)) () in
  Printf.printf "Waiting for b to finish\n%!";
  await b;
  Printf.printf "Waiting for a to finish\n%!";
  await a;
  Printf.printf "Done\n%!"


let () = Runtime.run f
