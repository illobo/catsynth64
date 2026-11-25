; ------------------------------------------------------------------ CatDrive
; Songs and the directory through CatBoot's drive code, the band playing.
; After a fast boot CatBoot leaves its code in the 1541, waiting, and "CD"
; and the device at $03f0 (cd_init reads it, then clears it). The disk
; page then loads a song (cd_loadn) and reads the directory (cd_dirread)
; over the same ATN-clocked link: the C64 makes every edge, the drive
; answers each and holds its answer until the next, so a C64 late to read
; (an interrupt, a badline, the music) reads it all the same. The receive
; loops run the main loop's frame work (music, poses, the stage) once a
; frame themselves, in the lower border as the main loop does.
; Anything else on the disk (save, delete, rename) goes through the KERNAL:
; dio_begin sends "back to the DOS" first (cd_quit), and so does a failed
; transfer (the KERNAL's way then tries it again and says what is wrong).
;
; The link (catboot.asm's drive code is the other side):
;   C64 -> drive: a byte as four ATN edges (pulled, let go, pulled, let
;   go), each with a bit pair on the lines at the same time: DATA the low
;   bit, CLK the high, pulled = 1, the low pair first. $c1 + 16 name bytes
;   ($a0 padded): a file; $c2: the directory; $c3: back to the DOS.
;   drive -> C64: blocks. Ready: CLK pulled, DATA let go; then a length
;   byte (0 the end, $ff an error) and as many bytes, four ATN edges a
;   byte, a pair read after each (bits 7-6 of $dd00); then one more edge,
;   on which the drive is busy again. A file: its blocks' bytes (the load
;   address first). The directory: the BAM's sector bytes 2-255, then each
;   directory sector's.
; A line is pulled by making it an input in $dd02 (its $dd00 latch 0).

CD_LOAD = $c1
CD_DIR  = $c2
CD_QUIT = $c3
CD_REL  = $3f                   ; $dd02: ATN, CLK, DATA outputs: let go
CD_ATN  = $37                   ; ATN an input: pulled

; at the start: the drive's code waiting? (cd_on)
cd_init lda #0
        sta cd_on
        lda $03f0
        cmp #$43
        bne +
        lda $03f1
        cmp #$44
        bne +
        lda $03f2
        cmp #DISK_DEV
        bne +
        inc cd_on
+       lda #0                  ; (once: a restart finds the DOS's way)
        sta $03f0
        rts

; back to the DOS (the drive reads the BAM again: the KERNAL's next
; command waits for it)
cd_quit lda cd_on
        beq +
        jsr cd_bus
        lda #CD_QUIT
        jsr cd_send
        jsr cd_free
        lda #0
        sta cd_on
+       rts

; the latches of the bus lines 0, all let go
cd_bus  lda $dd00
        and #%11000111
        sta $dd00
cd_free lda #CD_REL
        sta $dd02
        rts

; send A (C64 -> drive): four edges, a pair with each; ~80 cycles apart,
; the drive's time to see the edge and read the pair
cd_send sta cd_acc
        lda #2
        sta cd_k
-       lda cd_acc
        and #3
        tax
        lda cd_pa,x
        sta $dd02               ; ATN pulled, the pair
        jsr cd_w60
        lsr cd_acc
        lsr cd_acc
        lda cd_acc
        and #3
        tax
        lda cd_pr,x
        sta $dd02               ; ATN let go, the next pair
        jsr cd_w60
        lsr cd_acc
        lsr cd_acc
        dec cd_k
        bne -
        rts
cd_w60  ldx #10
-       dex
        bne -
        rts
; $dd02 for a pair (bit 0 DATA, bit 1 CLK; 1 = pulled: an input)
cd_pa   .byte CD_ATN, CD_ATN & ~$20, CD_ATN & ~$10, CD_ATN & ~$30
cd_pr   .byte CD_REL, CD_REL & ~$20, CD_REL & ~$10, CD_REL & ~$30

; a byte from the drive (catboot.asm's getbyte, as it is)
cd_get  jsr cd_w26              ; (the drive's time to get the byte ready:
        jsr cd_w26              ; ~90 cycles since the last edge)
        jsr cd_w26
        lda #CD_ATN
        sta $dd02
        jsr cd_w26
        lda $dd00               ; pair 0 (bits 7-6), later at 1-0
        and #$c0
        lsr a
        lsr a
        sta cd_acc
        lda #CD_REL
        sta $dd02
        jsr cd_w26
        lda $dd00               ; pair 1
        and #$c0
        ora cd_acc
        lsr a
        lsr a
        sta cd_acc
        lda #CD_ATN
        sta $dd02
        jsr cd_w26
        lda $dd00               ; pair 2
        and #$c0
        ora cd_acc
        lsr a
        lsr a
        sta cd_acc
        lda #CD_REL
        sta $dd02
        jsr cd_w26
        lda $dd00               ; pair 3
        and #$c0
        ora cd_acc
        eor #$ff                ; (a pulled line reads 0)
        rts
cd_w26  nop                     ; jsr, 5 nops, rts, the lda: 26 cycles
        nop                     ; at least (later is fine: the drive
        nop                     ; holds its pair until the next edge)
        nop
        nop
        rts

; a block into dk_zp (free while no KERNAL call runs; 254 bytes at most):
; C clear, A = its length (Z: 0, the end); C set: an error, or no drive
; (nothing ready for ~10 seconds)
cd_block
        lda #0
        sta cd_frames
        sta cd_frames+1
-       lda $dd00               ; ready: CLK pulled, DATA let go
        and #$c0
        cmp #$80
        beq +
        jsr cd_frame
        lda cd_frames+1
        cmp #2                  ; (512 frames)
        bcc -
        rts                     ; (C set)
+       jsr cd_w26              ; (the drive sets up the length byte)
        jsr cd_w26
        jsr cd_get
        sta cd_n
        cmp #$ff
        beq cdb8
        cmp #0
        beq cdb9
        ldy #0
-       sty cd_y
        jsr cd_frame
        jsr cd_get
        ldy cd_y
        sta dk_zp,y
        iny
        cpy cd_n
        bne -
cdb9    jsr cd_end
        lda cd_n
        clc
        rts
cdb8    jsr cd_end
        sec
        rts
; the block's end: one more edge (the drive shows busy on it)
cd_end  lda #CD_ATN
        sta $dd02
        jsr cd_w26
        jsr cd_w26
        lda #CD_REL
        sta $dd02
        rts

; the main loop's frame work, once a frame from line 250 on
cd_frame
        lda $d011
        bmi cdf1                ; (lines 256 on)
        lda $d012
        cmp #$fa
        bcs cdf1
        lda #0
        sta cd_fdone
        rts
cdf1    lda cd_fdone
        bne cdf9
        inc cd_fdone
        inc cd_frames
        bne +
        inc cd_frames+1
+       jsr music
        jsr slots_tick
        jsr pulse_frame
        jsr poses
        jsr screen_frame
        inc frame
cdf9    rts

; the end of a transfer: the bus let go, and not line 250 still (the main
; loop's frame would come twice)
cd_done jsr cd_free
-       lda $d012
        cmp #$fa
        beq -
        rts

; the file named (disk_setname) into disk_buf, then song_unpack, as
; disk_loadn. Out: C clear ok; C set, A = disk_err: DE_BADFILE (cd_on
; still 1), or the drive failed (cd_on 0: back to the DOS, the KERNAL's
; way to try)
cd_loadn
        jsr cd_bus
        lda #CD_LOAD
        jsr cd_send
        ldy #0                  ; the name, $a0 padded
-       sty cd_y
        lda #$a0
        cpy dk_nlen
        bcs +
        lda dk_cmd+3,y
+       jsr cd_send
        ldy cd_y
        iny
        cpy #16
        bne -
        jsr cd_free
        lda #0
        sta cd_len
        sta cd_len+1
cdl1    jsr cd_block            ; the blocks: after the load address, at
        bcs cdlerr              ; most DK_PACKMAX bytes into disk_buf
        beq cdl3
        ldx #0                  ; byte cd_len of the file: at disk_buf +
cdl2    lda cd_len+1            ; cd_len - 2 (the load address not kept,
        bne +                   ; past 256 bytes none: too long)
        ldy cd_len
        cpy #2
        bcc cdl5
        lda dk_zp,x
        sta disk_buf-2,y
        jmp cdl5
+       cmp #1
        bne cdl5
        ldy cd_len
        cpy #2
        bcs cdl5
        lda dk_zp,x
        sta disk_buf+254,y
cdl5    inc cd_len
        bne +
        inc cd_len+1
+       inx
        cpx cd_n
        bne cdl2
        jmp cdl1
cdl3    jsr cd_done
        sec                     ; the length after the load address
        lda cd_len
        sbc #2
        tay
        lda cd_len+1
        sbc #0
        bcc cdlbad              ; (less than 2)
        beq +
        cmp #1                  ; 256 exactly: A = 0
        bne cdlbad
        cpy #0
        bne cdlbad
        beq cdl4
+       cpy #0
        beq cdlbad              ; (empty)
cdl4    tya
        jsr song_unpack
        bcs cdlbad
        lda #0
        sta disk_err
        clc
        rts
cdlbad  lda #DE_BADFILE
        sta disk_err
        sec
        rts
cdlerr  jsr cd_done
        jsr cd_quit
        sec
        rts

; the directory into the disk page's list, as dir_read: C clear ok; C set
; when the drive failed (cd_on 0: the KERNAL's way to try)
cd_dirread
        lda #0
        sta disk_dos
        sta disk_st
        sta dvalid
        jsr dir_clear
        jsr cd_bus
        lda #CD_DIR
        jsr cd_send
        jsr cd_free
        jsr cd_block            ; the BAM's sector
        bcs cdlerr
        beq cdlerr
        lda #$22                ; line 0: "NAME" ID DOS-type (as the
        sta dlbuf               ; listing has it: $a0 a space)
        ldx #0
-       lda dk_zp+$8e,x         ; (the sector's $90-$9f)
        jsr cd_sp
        sta dlbuf+1,x
        inx
        cpx #16
        bne -
        lda #$22
        sta dlbuf+17
        lda #$20
        sta dlbuf+18
        ldx #0
-       lda dk_zp+$a0,x         ; ($a2-$a6: ID, $a0, DOS type)
        jsr cd_sp
        sta dlbuf+19,x
        inx
        cpx #5
        bne -
        lda #24
        jsr cd_line0
        lda #0                  ; the blocks free: tracks 1-35 but 18
        sta cd_free16
        sta cd_free16+1
        ldx #2                  ; (track t's count: the sector's 4t)
-       cpx #2+17*4
        beq +
        lda dk_zp,x
        clc
        adc cd_free16
        sta cd_free16
        bcc +
        inc cd_free16+1
+       inx
        inx
        inx
        inx
        cpx #2+35*4
        bne -
        lda #1
        sta dline
cdd1    jsr cd_block            ; the directory's sectors
        bcc +
        jmp cdlerr
+       bne +
        jmp cdd9
+
        ldx #0                  ; the entries: 0, 32, ... 224
cdd2    stx cd_e
        lda dk_zp,x             ; the type (0: none)
        beq cdd5
        sta cd_t
        lda dk_zp+28,x          ; the blocks
        sta dblk
        lda dk_zp+29,x
        sta dblk+1
        lda #$22
        sta dlbuf
        ldy #1
-       lda dk_zp+3,x           ; the name, to its padding
        cmp #$a0
        beq +
        sta dlbuf,y
        inx
        iny
        cpy #17
        bne -
+       lda #$22
        sta dlbuf,y
        iny
        lda #$20
        sta dlbuf,y
        iny
        lda cd_t
        bmi +
        lda #$2a                ; "*": not closed
        sta dlbuf,y
        iny
+       lda cd_t
        and #7
        cmp #5
        bcs +                   ; (no such type: none)
        sta cd_t
        asl a
        adc cd_t
        tax
        lda dtypes,x
        sta dlbuf,y
        lda dtypes+1,x
        sta dlbuf+1,y
        lda dtypes+2,x
        sta dlbuf+2,y
        iny
        iny
        iny
+       tya
        jsr cd_line
        inc dline
        bne cdd5
        dec dline
cdd5    lda cd_e
        clc
        adc #32
        tax
        bcc cdd2
        jmp cdd1
cdd9    jsr cd_done
        lda cd_free16           ; the last line: the blocks free (no quote)
        sta dblk
        lda cd_free16+1
        sta dblk+1
        lda #0
        jsr cd_line
        inc dvalid
        lda #0
        sta disk_err
        clc
        rts
; a line of A bytes in dlbuf to dir_line (line 0: no blocks)
cd_line0
        ldx #0
        stx dline
        stx dblk
        stx dblk+1
cd_line sta dllen
        tay
        lda #0
        sta dlbuf,y
        sta dlbuf+1,y
        sta dlbuf+2,y
        jmp dir_line
; $a0 (the padding) as a space
cd_sp   cmp #$a0
        bne +
        lda #$20
+       rts

cd_on   .byte 0                 ; 1: CatBoot's code waits in the drive
cd_acc  .byte 0
cd_k    .byte 0
cd_n    .byte 0
cd_y    .byte 0
cd_e    .byte 0
cd_t    .byte 0
cd_fdone .byte 0
cd_frames .word 0
cd_len  .word 0
cd_free16 .word 0
