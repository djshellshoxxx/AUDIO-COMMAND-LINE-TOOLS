; wavheal - BATCH repair of WAV headers left broken by a crashed recorder, DAW, phone app or full disk:
; the RIFF and data size fields are still 0 / 0xFFFFFFFF / larger than the file, so editors refuse to open
; audio that is actually all there. Rewrites ONLY the two size fields, in place (8 bytes), rounding the data
; size down to whole sample frames. Healthy files are left untouched. RF64 files are not modified.
; x86-64 Linux, NASM, no libc, ~1 KB static binary.
;   build: nasm -f elf64 wavheal.asm -o wavheal.o && ld -o wavheal wavheal.o
;   usage: ./wavheal FILE.wav [FILE.wav ...]        exit status = number of files that failed
BITS 64
%define SYS_READ 0
%define SYS_WRITE 1
%define SYS_OPEN 2
%define SYS_CLOSE 3
%define SYS_LSEEK 8
%define SYS_PWRITE 18
%define SYS_EXIT 60

section .bss
buf     resb 4096
numbuf  resb 24
nread   resq 1
fsize   resq 1
blkalign resq 1
dpos    resq 1
field   resd 1

section .data
s_usage db "usage: wavheal FILE.wav [FILE.wav ...]  - repairs RIFF/data sizes of crash-truncated WAVs in place", 10
l_usage equ $ - s_usage
s_open  db ": cannot open read/write", 10
l_open  equ $ - s_open
s_nowav db ": not a RIFF/WAVE file (skipped)", 10
l_nowav equ $ - s_nowav
s_nodat db ": no data chunk in the first 4 KB (skipped)", 10
l_nodat equ $ - s_nodat
s_big   db ": larger than 4 GB, needs RF64 (skipped)", 10
l_big   equ $ - s_big
s_ok    db ": header OK", 10
l_ok    equ $ - s_ok
s_fixd  db ": FIXED data size -> "
l_fixd  equ $ - s_fixd
s_fixr  db " RIFF size -> "
l_fixr  equ $ - s_fixr
s_byt   db " bytes", 10
l_byt   equ $ - s_byt

section .text
global _start
_start:
    mov     r12, [rsp]              ; argc
    lea     r13, [rsp + 8]          ; argv
    cmp     r12, 2
    jge     .args
    mov     rsi, s_usage
    mov     rdx, l_usage
    call    print
    mov     edi, 2
    jmp     exit
.args:
    xor     r15d, r15d              ; failure count
    mov     ebx, 1
.next:
    cmp     rbx, r12
    jge     .done
    mov     rdi, [r13 + rbx * 8]
    call    heal
    add     r15, rax
    inc     rbx
    jmp     .next
.done:
    mov     rdi, r15
exit:
    mov     eax, SYS_EXIT
    syscall

; print(rsi=ptr, rdx=len) -> stdout
print:
    mov     eax, SYS_WRITE
    mov     edi, 1
    syscall
    ret

; printz(rsi=NUL-terminated string)
printz:
    xor     edx, edx
.l: cmp     byte [rsi + rdx], 0
    je      print
    inc     rdx
    jmp     .l

; printnum(rax=unsigned value)
printnum:
    lea     rsi, [numbuf + 23]
    mov     ecx, 10
    xor     edx, edx
    mov     byte [rsi], 0
.d: xor     edx, edx
    div     rcx
    add     dl, '0'
    dec     rsi
    mov     [rsi], dl
    test    rax, rax
    jnz     .d
    jmp     printz

; pwrite32(rbp=fd, eax=value, r10=offset)
pwrite32:
    mov     [field], eax
    mov     eax, SYS_PWRITE
    mov     rdi, rbp
    mov     rsi, field
    mov     edx, 4
    syscall
    ret

; heal(rdi=path) -> rax 0 ok / 1 failed
heal:
    push    rbx
    mov     r14, rdi
    mov     rsi, rdi
    call    printz                  ; "path"
    mov     eax, SYS_OPEN
    mov     rdi, r14
    mov     esi, 2                  ; O_RDWR
    syscall
    test    rax, rax
    js      .e_open
    mov     rbp, rax                ; fd
    mov     eax, SYS_READ
    mov     rdi, rbp
    mov     rsi, buf
    mov     edx, 4096
    syscall
    mov     [nread], rax
    cmp     rax, 12
    jl      .e_nowav
    cmp     dword [buf], 'RIFF'
    jne     .e_nowav
    cmp     dword [buf + 8], 'WAVE'
    jne     .e_nowav
    mov     eax, SYS_LSEEK
    mov     rdi, rbp
    xor     esi, esi
    mov     edx, 2                  ; SEEK_END
    syscall
    mov     [fsize], rax
    mov     rcx, 0xFFFFFFFF + 8
    cmp     rax, rcx
    ja      .e_big
    mov     qword [blkalign], 1
    mov     rbx, 12                 ; chunk walk position
.walk:
    lea     rax, [rbx + 8]
    cmp     rax, [nread]
    jg      .e_nodat
    mov     eax, [buf + rbx]
    cmp     eax, 'data'
    je      .found
    cmp     eax, 'fmt '
    jne     .skip
    lea     rax, [rbx + 22]
    cmp     rax, [nread]
    jg      .skip
    movzx   eax, word [buf + rbx + 20]   ; nBlockAlign
    test    eax, eax
    jz      .skip
    mov     [blkalign], rax
.skip:
    mov     eax, [buf + rbx + 4]
    lea     rbx, [rbx + rax + 8]
    and     eax, 1
    add     rbx, rax                ; RIFF pad byte
    jmp     .walk
.found:
    mov     [dpos], rbx
    mov     rax, [fsize]
    sub     rax, rbx
    sub     rax, 8                  ; bytes really available after the data header
    jge     .avail
    xor     eax, eax
.avail:
    mov     r8, rax
    mov     ecx, [buf + rbx + 4]    ; declared data size
    xor     r9d, r9d                ; r9 = 1 if anything was fixed
    test    ecx, ecx
    jz      .fixdata
    cmp     ecx, 0xFFFFFFFF
    je      .fixdata
    cmp     rcx, r8
    jbe     .riff
.fixdata:
    mov     rax, r8
    xor     edx, edx
    div     qword [blkalign]
    sub     r8, rdx                 ; whole frames only
    mov     eax, r8d
    mov     r10, [dpos]
    add     r10, 4
    call    pwrite32
    mov     r9d, 1
.riff:
    mov     rax, [fsize]
    sub     rax, 8
    mov     ecx, [buf + 4]
    test    r9d, r9d
    jnz     .fixriff
    test    ecx, ecx
    jz      .fixriff
    cmp     rcx, rax
    jbe     .report
.fixriff:
    mov     r10d, 4
    push    rax
    call    pwrite32
    pop     rax
    mov     r9d, 1
.report:
    push    rax
    mov     eax, SYS_CLOSE
    mov     rdi, rbp
    syscall
    pop     rbx                     ; riff value
    test    r9d, r9d
    jnz     .say_fixed
    mov     rsi, s_ok
    mov     rdx, l_ok
    call    print
    xor     eax, eax
    pop     rbx
    ret
.say_fixed:
    mov     rsi, s_fixd
    mov     rdx, l_fixd
    call    print
    mov     rax, r8
    call    printnum
    mov     rsi, s_fixr
    mov     rdx, l_fixr
    call    print
    mov     rax, rbx
    call    printnum
    mov     rsi, s_byt
    mov     rdx, l_byt
    call    print
    xor     eax, eax
    pop     rbx
    ret
.e_open:
    mov     rsi, s_open
    mov     rdx, l_open
    jmp     .fail
.e_nowav:
    mov     rsi, s_nowav
    mov     rdx, l_nowav
    jmp     .fail_close
.e_nodat:
    mov     rsi, s_nodat
    mov     rdx, l_nodat
    jmp     .fail_close
.e_big:
    mov     rsi, s_big
    mov     rdx, l_big
.fail_close:
    push    rsi
    push    rdx
    mov     eax, SYS_CLOSE
    mov     rdi, rbp
    syscall
    pop     rdx
    pop     rsi
.fail:
    call    print
    mov     eax, 1
    pop     rbx
    ret
