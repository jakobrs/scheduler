#include <caml/memory.h>
#include <caml/mlvalues.h>

#include <sys/epoll.h>
#include <sys/timerfd.h>

extern "C" {
CAMLprim value ocaml_epoll_create(value unit) {
    CAMLparam1(unit);
    int fd = epoll_create1(EPOLL_CLOEXEC);
    CAMLreturn(Val_int(fd));
}

CAMLprim value ocaml_epoll_register(value epfd, value flags, value fd) {
    CAMLparam2(epfd, fd);
    int events = 0;
    if (Int_val(flags) & 1) events |= EPOLLIN;
    if (Int_val(flags) & 2) events |= EPOLLOUT;
    epoll_event ev = {
        .events = EPOLLET | events,
        .data = {
            .fd = Int_val(fd),
        },
    };
    epoll_ctl(Int_val(epfd), EPOLL_CTL_ADD, Int_val(fd), &ev);
    CAMLreturn(Val_unit);
}

CAMLprim value ocaml_epoll_wait_one(value epfd, value timeout) {
    CAMLparam2(epfd, timeout);
    epoll_event ev;
    int count = epoll_wait(Int_val(epfd), &ev, 1, Int_val(timeout));
    int res = count == 0 ? -1 : ev.data.fd;
    CAMLreturn(Val_int(res));
}

CAMLprim value ocaml_timerfd_create(value unit) {
    CAMLparam1(unit);
    int res = timerfd_create(CLOCK_MONOTONIC, TFD_NONBLOCK | TFD_CLOEXEC);
    CAMLreturn(Val_int(res));
}

CAMLprim value ocaml_timerfd_settime(value timer, value secs, value nanosecs) {
    CAMLparam3(timer, secs, nanosecs);
    auto time = timespec {
        .tv_sec = Int_val(secs),
        .tv_nsec = Int_val(nanosecs),
    };
    auto new_value = itimerspec {
        .it_interval = time,
        .it_value = time,
    };
    timerfd_settime(Int_val(timer), 0, &new_value, nullptr);
    CAMLreturn(Val_unit);
}
}
