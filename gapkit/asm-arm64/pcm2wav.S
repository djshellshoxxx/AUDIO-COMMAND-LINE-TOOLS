// pcm2wav - wrap HEADERLESS raw PCM (ADC/I2S captures, `arecord -t raw`, DSP/microcontroller dumps, SDR
// audio, game/firmware extracts) into a valid WAV so any editor can open it. Built for Raspberry Pi and other
// ARM64 boards: a tiny static binary with no libc that streams 64 KB at a time (any file size up to 4 GB).
// AArch64 Linux, GNU as.
//   build: aarch64-linux-gnu-as pcm2wav.S -o pcm2wav.o && aarch64-linux-gnu-ld -o pcm2wav pcm2wav.o
//          (on the Pi itself: as pcm2wav.S -o pcm2wav.o && ld -o pcm2wav pcm2wav.o)
//   usage: pcm2wav IN.raw OUT.wav RATE CHANNELS BITS     BITS = 8 | 16 | 24 | 32 (signed int) | 32f (float)
//   A trailing partial frame is dropped so the WAV is always frame-aligned. Exit 0 ok, 1 error, 2 usage.
        .equ SYS_OPENAT, 56
        .equ SYS_CLOSE, 57
        .equ SYS_READ, 63
        .equ SYS_WRITE, 64
        .equ SYS_FSTAT, 80
        .equ SYS_EXIT, 93
        .equ AT_FDCWD, -100

        .bss
        .balign 16
hdr:    .skip 44
stat:   .skip 128
num:    .skip 24
buf:    .skip 65536

        .data
usage:  .ascii "usage: pcm2wav IN.raw OUT.wav RATE CHANNELS BITS   (BITS 8|16|24|32|32f)\n"
        .equ usage_len, . - usage
e_args: .ascii "pcm2wav: bad RATE/CHANNELS/BITS\n"
        .equ e_args_len, . - e_args
e_in:   .ascii "pcm2wav: cannot open input\n"
        .equ e_in_len, . - e_in
e_out:  .ascii "pcm2wav: cannot create output\n"
        .equ e_out_len, . - e_out
e_big:  .ascii "pcm2wav: input larger than 4 GB WAV limit\n"
        .equ e_big_len, . - e_big
e_io:   .ascii "pcm2wav: read/write error\n"
        .equ e_io_len, . - e_io
m_a:    .ascii "pcm2wav: wrote "
        .equ m_a_len, . - m_a
m_b:    .ascii " frames ("
        .equ m_b_len, . - m_b
m_c:    .ascii " data bytes)\n"
        .equ m_c_len, . - m_c

        .text
        .global _start
_start:
        ldr     x19, [sp]               // argc
        add     x20, sp, #8             // argv
        cmp     x19, #6
        b.eq    1f
        adr     x1, usage
        mov     x2, #usage_len
        bl      print
        mov     x0, #2
        b       exit
1:      ldr     x0, [x20, #24]
        bl      atou
        mov     x21, x0                 // rate
        ldr     x0, [x20, #32]
        bl      atou
        mov     x22, x0                 // channels
        ldr     x0, [x20, #40]
        bl      atou
        mov     x23, x0                 // bits
        mov     x24, #1                 // format tag: 1 = PCM
        ldrb    w2, [x1]                // char after the digits
        cmp     w2, #'f'
        b.ne    2f
        mov     x24, #3                 // 3 = IEEE float
        cmp     x23, #32
        b.ne    bad_args
2:      cbz     x21, bad_args
        cbz     x22, bad_args
        cmp     x22, #32
        b.hi    bad_args
        cmp     x23, #8
        b.eq    3f
        cmp     x23, #16
        b.eq    3f
        cmp     x23, #24
        b.eq    3f
        cmp     x23, #32
        b.ne    bad_args
3:      lsr     x25, x23, #3
        mul     x25, x25, x22           // block align = bytes per frame
        // open input, get its size
        mov     x0, #AT_FDCWD
        ldr     x1, [x20, #8]
        mov     x2, #0                  // O_RDONLY
        mov     x8, #SYS_OPENAT
        svc     #0
        tbnz    x0, #63, bad_in
        mov     x26, x0                 // in fd
        adr     x1, stat
        mov     x8, #SYS_FSTAT
        svc     #0
        tbnz    x0, #63, bad_in
        adr     x1, stat
        ldr     x27, [x1, #48]          // st_size
        udiv    x2, x27, x25
        mul     x27, x2, x25            // frame-aligned data size
        mov     x3, #0xFFFFFFFF
        sub     x3, x3, #36
        cmp     x27, x3
        b.hi    too_big
        // create output
        mov     x0, #AT_FDCWD
        ldr     x1, [x20, #16]
        mov     x2, #0x241              // O_WRONLY|O_CREAT|O_TRUNC
        mov     x3, #0644
        mov     x8, #SYS_OPENAT
        svc     #0
        tbnz    x0, #63, bad_out
        mov     x28, x0                 // out fd
        // build the 44-byte canonical header
        adr     x9, hdr
        ldr     w10, =0x46464952        // "RIFF"
        str     w10, [x9, #0]
        add     w10, w27, #36
        str     w10, [x9, #4]
        ldr     w10, =0x45564157        // "WAVE"
        str     w10, [x9, #8]
        ldr     w10, =0x20746d66        // "fmt "
        str     w10, [x9, #12]
        mov     w10, #16
        str     w10, [x9, #16]
        strh    w24, [x9, #20]          // format tag
        strh    w22, [x9, #22]          // channels
        str     w21, [x9, #24]          // sample rate
        mul     w10, w21, w25
        str     w10, [x9, #28]          // byte rate
        strh    w25, [x9, #32]          // block align
        strh    w23, [x9, #34]          // bits per sample
        ldr     w10, =0x61746164        // "data"
        str     w10, [x9, #36]
        str     w27, [x9, #40]
        mov     x0, x28
        mov     x1, x9
        mov     x2, #44
        mov     x8, #SYS_WRITE
        svc     #0
        cmp     x0, #44
        b.ne    io_err
        // stream copy exactly x27 bytes
        mov     x19, x27                // remaining
copy:   cbz     x19, finished
        mov     x2, #65536
        cmp     x19, x2
        csel    x2, x19, x2, lo
        mov     x0, x26
        adr     x1, buf
        mov     x8, #SYS_READ
        svc     #0
        cmp     x0, #0
        b.le    io_err
        mov     x2, x0
        sub     x19, x19, x0
        mov     x0, x28
        adr     x1, buf
        mov     x8, #SYS_WRITE
        svc     #0
        tbnz    x0, #63, io_err
        b       copy
finished:
        mov     x0, x28
        mov     x8, #SYS_CLOSE
        svc     #0
        adr     x1, m_a
        mov     x2, #m_a_len
        bl      print
        udiv    x0, x27, x25
        bl      printnum
        adr     x1, m_b
        mov     x2, #m_b_len
        bl      print
        mov     x0, x27
        bl      printnum
        adr     x1, m_c
        mov     x2, #m_c_len
        bl      print
        mov     x0, #0
exit:   mov     x8, #SYS_EXIT
        svc     #0

bad_args: adr   x1, e_args
        mov     x2, #e_args_len
        b       fail
bad_in: adr     x1, e_in
        mov     x2, #e_in_len
        b       fail
bad_out: adr    x1, e_out
        mov     x2, #e_out_len
        b       fail
too_big: adr    x1, e_big
        mov     x2, #e_big_len
        b       fail
io_err: adr     x1, e_io
        mov     x2, #e_io_len
fail:   mov     x0, #2                  // stderr
        mov     x8, #SYS_WRITE
        svc     #0
        mov     x0, #1
        b       exit

// print(x1=ptr, x2=len) to stdout
print:  mov     x0, #1
        mov     x8, #SYS_WRITE
        svc     #0
        ret

// atou(x0=string) -> x0 value, x1 = pointer to first non-digit
atou:   mov     x1, x0
        mov     x0, #0
        mov     x3, #10
4:      ldrb    w2, [x1]
        sub     w2, w2, #'0'
        cmp     w2, #9
        b.hi    5f
        madd    x0, x0, x3, x2
        add     x1, x1, #1
        b       4b
5:      ret

// printnum(x0=unsigned) to stdout
printnum:
        adr     x1, num
        add     x1, x1, #24
        mov     x2, #0
        mov     x3, #10
6:      udiv    x4, x0, x3
        msub    x5, x4, x3, x0
        add     w5, w5, #'0'
        sub     x1, x1, #1
        strb    w5, [x1]
        add     x2, x2, #1
        mov     x0, x4
        cbnz    x0, 6b
        mov     x9, x30
        bl      print
        mov     x30, x9
        ret
