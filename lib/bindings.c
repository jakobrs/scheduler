#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <sys/epoll.h>
#include <sys/timerfd.h>

value ocaml_epoll_create(value unit) {
    CAMLparam1(unit);
    int fd = epoll_create1(EPOLL_CLOEXEC);
    CAMLreturn(Val_int(fd));
}

value ocaml_epoll_register(value epfd, value fd) {
    CAMLparam2(epfd, fd);
    struct epoll_event ev = {
        .events = EPOLLET | EPOLLIN,
        .data.fd = Int_val(fd),
    };
    epoll_ctl(Int_val(epfd), EPOLL_CTL_ADD, Int_val(fd), &ev);
    CAMLreturn(Val_unit);
}

value ocaml_epoll_wait_one(value epfd, value timeout) {
    CAMLparam2(epfd, timeout);
    struct epoll_event ev;
    int count = epoll_wait(Int_val(epfd), &ev, 1, Int_val(timeout));
    int res = count == 0 ? -1 : ev.data.fd;
    CAMLreturn(Val_int(res));
}

value ocaml_timerfd_create(value unit) {
    CAMLparam1(unit);
    int res = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    CAMLreturn(Val_int(res));
}

value ocaml_timerfd_settime(value timer, value secs, value nanosecs) {
    CAMLparam3(timer, secs, nanosecs);
    struct itimerspec new_value = {
        .it_interval.tv_sec = Int_val(secs),
        .it_interval.tv_nsec = Int_val(nanosecs),
        .it_value.tv_sec = Int_val(secs),
        .it_value.tv_nsec = Int_val(nanosecs),
    };
    timerfd_settime(Int_val(timer), 0, &new_value, nullptr);
    CAMLreturn(Val_unit);
}
