open Scheduler

let f () =
  let open Runtime.Prelude in
  let module Timer = Runtime.Timer in

  let stdin = Epoll.get_stdin () in
  let buf = Bytes.create 20 in
  let n = Epoll.read ~fd:stdin ~buf ~count:10 in
  Printf.printf "Read %d bytes\n%!" n;

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
