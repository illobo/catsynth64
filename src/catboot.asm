; ------------------------------------------------------------------ CatBoot
; CatSynth 64's boot code, "CATBOOT" on the disk (at $c000: the autoboot
; file "CATSYNTH64", autoboot.asm, loads it and starts it). It loads the
; program, "CATSYNTH64 MAIN", and starts it.
;
; On a 1541 alone on the bus (its ROM's version string ends "1541": $e5c6
; = "4"; no device 8-11 but it) the drive gets its code (M-W, M-E) and
; reads the file itself: the DOS only seeks (job $b0); the code reads the
; header and the data block's 325 GCR bytes, decodes them (two 32-entry
; tables), checks the block ID and checksum (retrying), and sends the
; bytes over an ATN-clocked 2-bit link, then waits for CatSynth's
; commands (songs, the directory; "CD" and the device at $03f0 say so),
; or goes back to the DOS through Initialize ($d005). Anything else
; (another drive, an SD2IEC, more devices on the bus) loads the file
; through the KERNAL. A JiffyDOS KERNAL and drive ROM are fine: CatBoot
; loads faster than the KERNAL either way, and only its code, left in the
; drive, lets CatSynth load songs with the band playing (catdrive.asm).
;
; The link: the C64 never writes the bus bits of $dd00 (they stay 0); it
; pulls a line by making it an input in $dd02 (the pull-up drives the
; inverter: the line goes low), so the VIC bank bits are never touched.
; Per byte four ATN edges (pulled, let go, pulled, let go); after each the
; drive puts a bit pair on DATA (high bit) and CLK (low bit), low pair
; first, with ATNA set to ATN's new state in the same store (the 1541
; pulls DATA itself while they differ). The C64 reads 20+ us after each
; edge, so it may be interrupted anywhere (badlines, sprites, raster
; interrupts): no cycle counting, PAL or NTSC. A block: the drive shows
; ready (CLK low, DATA high), the C64 reads a length byte (1-254 bytes
; follow; 0: the file's end, $ff: an error) and the bytes, then gives one
; more ATN edge, on which the drive shows busy (DATA low).
;
;   64tass -C -a -D CB_SYS=<the program's SYS> src/catboot.asm -o build/catboot.prg

.weak
CB_SYS  = 2061                  ; the program's start (its SYS line)
.endweak

SETLFS  = $ffba
SETNAM  = $ffbd
OPEN    = $ffc0
CHKIN   = $ffc6
CHKOUT  = $ffc9
CHRIN   = $ffcf
CHROUT  = $ffd2
CLRCHN  = $ffcc
LOAD    = $ffd5
READST  = $ffb7
LISTEN  = $ffb1
SECOND  = $ff93
UNLSN   = $ffae

CB      = $c000                 ; where it runs (the program loads below it)
DDR_REL = $3f                   ; $dd02: ATN, CLK, DATA outputs (0: let go)
DDR_ATN = $37                   ; ATN an input: pulled
cb_ptr  = $fb                   ; where the next byte goes
DRIVE   = $0446                 ; the drive code's home ($0446-$07ff)

        * = CB                  ; (loaded there by the autoboot file,
cb_main                         ; autoboot.asm: out of the program's way)
        lda $ba                 ; the drive it was loaded from (8 if none)
        cmp #8
        bcs +
        lda #8
+       sta cb_dev
        jsr alone               ; ATN as the clock: no other device may be
        bcs kload               ; on the bus (it would answer every edge)
        lda #15                 ; the command channel
        ldx cb_dev
        ldy #15
        jsr SETLFS
        lda #0
        jsr SETNAM
        jsr OPEN
        bcs kload
        ldx #<cb_mr             ; M-R $e5c6, 1 byte: the model digit
        ldy #>cb_mr
        lda #6
        jsr cb_cmd
        ldx #15
        jsr CHKIN
        jsr CHRIN
        pha
        jsr CLRCHN
        jsr READST
        tax
        pla
        cpx #0
        bne kload               ; no answer
        cmp #"4"
        bne kload               ; not a 1541
        jsr upload
        jsr receive
        bcc cbfast
kload   lda #0                  ; the KERNAL's way (and the files closed;
        sta $98                 ; no marker: the drive is the DOS's)
        sta $03f0
        lda #1
        ldx cb_dev
        ldy #1
        jsr SETLFS
        lda #len(CB_NAME)
        ldx #<cb_name
        ldy #>cb_name
        jsr SETNAM
        lda #0
        jsr LOAD
        bcs fail
        bcc start
cbfast  lda #$43                ; the marker for CatSynth: "CD" and the
        sta $03f0               ; device at $03f0 (the tape buffer): the
        lda #$44                ; drive's code waits for its commands
        sta $03f1
        lda cb_dev
        sta $03f2
start   lda #0                  ; no file left open (the command channel's
        sta $98                 ; entry, never closed: the drive was busy)
        jmp CB_SYS
fail    ldx #0
-       lda cb_err,x
        beq +
        jsr CHROUT
        inx
        bne -
+       rts

; C set when a device 8-11 other than ours answers on the bus
alone   lda #8
        sta cb_n
-       lda cb_n
        cmp cb_dev
        beq +
        lda #0
        sta $90
        lda cb_n
        jsr LISTEN
        lda #$6f
        jsr SECOND
        jsr UNLSN
        lda $90
        bpl ++                  ; (bit 7: not present)
+       inc cb_n
        lda cb_n
        cmp #12
        bne -
        clc
        rts
+       sec
        rts

; send the command at X/Y, A bytes long, on the command channel
cb_cmd  stx cb_ptr
        sty cb_ptr+1
        sta cb_n
        ldx #15
        jsr CHKOUT
        ldy #0
-       lda (cb_ptr),y
        jsr CHROUT
        iny
        cpy cb_n
        bne -
        jmp CLRCHN              ; (unlisten: the drive does it)

; the drive code to DRIVE and its tables to DDATA (M-W, 32 bytes at a
; time), then run it (M-E)
upload  lda #<dcode
        ldx #>dcode
        ldy #>dcode_end
        sta cb_src
        stx cb_src+1
        lda #<dcode_end
        sta cb_last
        sty cb_last+1
        lda #<DRIVE
        ldx #>DRIVE
        jsr upseg
        lda #<ddata
        sta cb_src
        lda #>ddata
        sta cb_src+1
        lda #<ddata_end
        sta cb_last
        lda #>ddata_end
        sta cb_last+1
        lda #<DDATA
        ldx #>DDATA
        jsr upseg
        ldx #<cb_me
        ldy #>cb_me
        lda #5
        jmp cb_cmd              ; M-E: the drive is ours until it is done

; cb_src..cb_last to the drive's A/X (M-W, 32 bytes a command, the last
; one only what is left: past $07ff the 1541's RAM wraps to its zero page,
; the job queue)
upseg   sta cb_mw+3
        stx cb_mw+4
up1     lda #32                 ; this command's length: 32, or what is left
        sta cb_mw+5
        sec
        lda cb_last
        sbc cb_src
        tax
        lda cb_last+1
        sbc cb_src+1
        bne +
        cpx #32
        bcs +
        stx cb_mw+5
+       ldx #15
        jsr CHKOUT
        ldy #0
-       lda cb_mw,y             ; "M-W", address, 32
        jsr CHROUT
        iny
        cpy #6
        bne -
        lda cb_src
        sta cb_ptr
        lda cb_src+1
        sta cb_ptr+1
        ldy #0
-       lda (cb_ptr),y
        jsr CHROUT
        iny
        cpy cb_mw+5
        bne -
        jsr CLRCHN
        clc
        lda cb_src
        adc #32
        sta cb_src
        bcc +
        inc cb_src+1
+       clc
        lda cb_mw+3
        adc #32
        sta cb_mw+3
        bcc +
        inc cb_mw+4
+       lda cb_src+1            ; all of it sent?
        cmp cb_last+1
        bcc up1
        bne +
        lda cb_src
        cmp cb_last
        bcc up1
+       rts

; the file from the drive: C clear when it all came, set on an error
receive sei
        lda $0318               ; RESTORE does nothing meanwhile
        sta cb_nmi
        lda $0319
        sta cb_nmi+1
        lda #<cb_rti
        sta $0318
        lda #>cb_rti
        sta $0319
        lda $dd00               ; the bus bits' latches 0: a line is pulled
        and #%11000111          ; only by making it an input in $dd02
        sta $dd00
        lda #DDR_REL
        sta $dd02
        jsr cready              ; the first block: its length
        jsr getbyte
        cmp #3
        bcc rerr                ; (0, 1, 2: no load address and data)
        cmp #$ff
        beq rerr
        sec
        sbc #2                  ; less the load address
        sta cb_n
        jsr getbyte             ; the load address
        sta cb_ptr
        jsr getbyte
        sta cb_ptr+1
rsec    ldy #0
-       jsr getbyte
        sta (cb_ptr),y
        inc cb_ptr
        bne +
        inc cb_ptr+1
+       dec cb_n
        bne -
        jsr cend                ; the block taken
        jsr cready              ; the next block: its length
        jsr getbyte
        cmp #$ff
        beq rerr
        sta cb_n
        cmp #0
        bne rsec
        jsr cend
        clc                     ; 0: the end
        .byte $24               ; (bit zp: skip the sec)
rerr    sec
        php
        lda #DDR_REL            ; all let go
        sta $dd02
        lda cb_nmi
        sta $0318
        lda cb_nmi+1
        sta $0319
        plp
        cli
        rts
cb_rti  rti

; wait for the drive's ready: CLK low, DATA high
cready
-       lda $dd00
        and #$c0
        cmp #$80
        bne -
        jsr wt20                ; (the drive sets up the length byte)
        jmp wt20

; the block's end: one more ATN edge (the drive shows busy on it)
cend    lda #DDR_ATN
        sta $dd02
        jsr wt20
        jsr wt20
        lda #DDR_REL
        sta $dd02
        rts

; a byte from the drive: four ATN edges, a bit pair read 20+ us after each
; (C64 cycles; NTSC's are shorter: 22 of them are still 21.5 us)
getbyte jsr wt20                ; (the drive's time to get the byte ready:
        jsr wt20                ; ~90 cycles since the last edge, ~110 with
        jsr wt20                ; the caller here)
        lda #DDR_ATN
        sta $dd02
        jsr wt20
        lda $dd00               ; pair 0 (bits 7-6), later at 1-0
        and #$c0
        lsr a
        lsr a
        sta cb_acc
        lda #DDR_REL
        sta $dd02
        jsr wt20
        lda $dd00               ; pair 1
        and #$c0
        ora cb_acc
        lsr a
        lsr a
        sta cb_acc
        lda #DDR_ATN
        sta $dd02
        jsr wt20
        lda $dd00               ; pair 2
        and #$c0
        ora cb_acc
        lsr a
        lsr a
        sta cb_acc
        lda #DDR_REL
        sta $dd02
        jsr wt20
        lda $dd00               ; pair 3
        and #$c0
        ora cb_acc
        eor #$ff                ; (a pulled line reads 0)
        rts
wt20    nop                     ; jsr, 3 nops, rts and the lda: 22 cycles
        nop                     ; from the $dd02 store to the $dd00 read
        nop                     ; (the drive answers within 15)
        rts


cb_dev  .byte 8
cb_n    .byte 0
cb_acc  .byte 0
cb_src  .word 0
cb_last .word 0
cb_nmi  .word 0
cb_mr   .text "m-r", $c6, $e5, 1    ; (-a: lower case = PETSCII capitals)
cb_me   .text "m-e", <DRIVE, >DRIVE
cb_mw   .text "m-w", 0, 0, 32
CB_NAME = "catsynth64 main"       ; (as the directory has it: capitals)
cb_name .text CB_NAME
cb_err  .text 13, "catboot: can't load catsynth64 main", 13, 0

; ------------------------------------------------------------------ the drive
; runs at DRIVE in the 1541, interrupts off except while the DOS seeks
; (job $b0 in slot 2: $02, track $0a). Memory: the raw GCR block at
; $0301-$0445 (325 bytes: groups 0-50 from $0301, 51-64 from $0400, so no
; group crosses a page), decoded there in place: the block ID at $0301,
; the sector's 256 bytes at $0302-$0401; the code and its data from $0446
; to $07ff (the BAM's buffer: Initialize reads it again at the end)
RETRY   = 8                     ; tries for a sector (a revolution each)
dcode
        .logical DRIVE
dstart  sei                     ; (the lines idle: not ready for the C64)
        lda #0
        sta dtrk                ; (no track yet: the first one seeks)
        jsr dfind               ; the boot: the program
        bcs dberr
        jsr dfile
        bcs dberr
        lda #0                  ; the end: then CatSynth's songs (didle)
        jsr dlast
        jmp didle
dberr   lda #$ff                ; an error: the C64 loads it through the
        jsr dlast               ; KERNAL, so the DOS back
        jmp dexit

; the commands, while CatSynth runs: the motor and LED off, the bus let go
; until ATN is pulled; then a byte from the C64: $c1 a file by name (16
; more bytes, $a0 padded), $c2 the directory (the BAM's sector, then 18/1
; on, a block each: their bytes 2-255), anything else back to the DOS
; (catdrive.asm is the other side)
didle   lda $1c00
        and #$f3
        sta $1c00
        lda #0
        sta $1800
-       bit $1800
        bpl -
        lda $1c00               ; the motor on (and the LED)
        ora #$0c
        sta $1c00
        jsr drecv
        cmp #$c1
        beq dcload
        cmp #$c2
        beq dcdir
dexit   lda #0
        sta $1800               ; the bus let go, ATNA 0
        lda #$ec                ; byte ready off, as the DOS keeps it idle
        sta $1c0c
        lda $1801               ; (the ATN flag the edges left: cleared)
        cli
        jmp $d005               ; back to the DOS through Initialize: the BAM
                                ; read again, its buffers and state its own
dcload  ldx #0                  ; the name
-       stx dent0
        jsr drecv
        ldx dent0
        sta dname,x
        inx
        cpx #16
        bne -
        jsr dspin
        jsr dfind
        bcs +
        jsr dfile
        bcs dcerr
dcok    lda #0
        .byte $2c
dcerr   lda #$ff
        jsr dlast
        jmp didle
dcdir   jsr dspin
        ldx #18                 ; the BAM's sector (its name, ID, free blocks)
        ldy #0
-       jsr dread
        bcs +
        lda #254
        sta dn
        jsr dblock
        ldx $0302               ; then the directory's chain
        beq ++
        ldy $0303
        jmp -
+       jmp dcerr
+       jmp dcok

; a byte from the C64: four ATN edges (pulled, let go, ...), after each a
; bit pair on DATA (low bit) and CLK (high bit), pulled = 1, low pair first
; (ATNA set to match first, so the 1541 lets DATA go before it is read)
drecv   ldx #2
drc1    bit $1800               ; ATN pulled
        bpl drc1
        lda #$10
        jsr drpair
-       bit $1800               ; ATN let go
        bmi -
        lda #$00
        jsr drpair
        dex
        bne drc1
        lda dacc
        rts
drpair  sta $1800               ; ATNA = ATN: the 1541 lets DATA go
        nop
        nop
        lda $1800               ; (bit 0 DATA in, bit 2 CLK in: 1 = pulled)
        lsr a                   ; C = DATA
        ror dacc
        and #$02                ; (CLK, shifted)
        cmp #$02                ; C = CLK
        ror dacc
        rts

; find the PRG named dname in the directory: C clear, X/Y its first track
; and sector; C set if not there (or a read error)
dfind   ldx #18
        ldy #1
dirsec  jsr dread
        bcs dfx
        ldy #2                  ; the entries: 2, 34, ... 226
dent    lda $0302,y
        cmp #$82                ; a PRG, closed
        bne dnext
        sty dent0
        ldx #0
-       lda $0305,y             ; its name
        cmp dname,x
        bne dnot
        iny
        inx
        cpx #16
        bne -
        ldy dent0               ; found: its first track/sector
        ldx $0303,y
        lda $0304,y
        tay
        clc
        rts
dnot    ldy dent0
dnext   tya
        clc
        adc #32
        tay
        bcc dent
        ldx $0302               ; the next directory sector
        beq +
        ldy $0303
        jmp dirsec
+       sec
dfx     rts

; the file from track X sector Y, a block a sector: C set on a read error
dfile   jsr dread
        bcs dfx
        lda $0302               ; the last one: its bytes 2..[link]
        bne +
        lda $0303
        sec
        sbc #1
        .byte $2c               ; (bit abs: skip the lda)
+       lda #254
        sta dn
        jsr dblock
        ldx $0302
        beq +
        ldy $0303
        jmp dfile
+       clc
        rts

; a block: dn bytes from $0304 (the sector's bytes 2 on), its length first
dblock  jsr dready
        lda dn
        jsr dsend
        ldy #2
-       lda $0302,y
        jsr dsend
        iny
        dec dn
        bne -
        jmp dbusy

; the last block: A alone (0 the end, $ff an error), then ATN let go
dlast   pha
        jsr dready
        pla
        jsr dsend
        jsr dbusy
-       bit $1800
        bmi -
        rts

; ready for a block: CLK low, DATA let go (it shows once ATN is let go)
dready  lda #$08
        sta $1800
        rts

; send A: four ATN edges, a pair after each (low pair first); keeps Y
dsend   pha
        and #$0f
        tax
        lda dta,x               ; pairs 0, 1: the low nibble
        sta dv
        lda dtb,x
        sta dv+1
        pla
        lsr a
        lsr a
        lsr a
        lsr a
        tax
        lda dta,x               ; pairs 2, 3: the high nibble
        sta dv+2
        lda dtb,x
        sta dv+3
        ldx #0                  ; the pairs: after each edge, at once
dsnd1   bit $1800               ; ATN pulled (bit 7)
        bpl dsnd1
        lda dv,x
        sta $1800
        inx
-       bit $1800               ; ATN let go
        bmi -
        lda dv,x
        sta $1800
        inx
        cpx #4
        bne dsnd1
        rts

; read track X sector Y: C clear and its 256 bytes at $0302, or C set
dread   stx dwt
        sty dws
        lda #RETRY
        sta dtry
dr0     lda dwt                 ; on its track? (else the DOS seeks)
        cmp dtrk
        beq dr1
        sta $0a
        lda #0
        sta $0b
        lda #$b0
        sta $02
        cli
-       lda $02
        bmi -
        sei
        cmp #1
        bne drfail
        lda dwt
        sta dtrk
dr1     lda #$ee                ; byte ready on (the DOS turns it off after
        sta $1c0c               ; each job)
        lda #64                 ; headers to look at
        sta dhc
dr2     jsr dsync
        bcs drfail
        ldy #0                  ; the header's first 5 GCR bytes: $08,
-       bvc -                   ; checksum, sector, track
        clv
        lda $1c01
        sta db0,y
        iny
        cpy #5
        bne -
        jsr dgcr
        lda do0
        cmp #$08
        bne drnext
        lda do2
        cmp dws
        bne drnext
        lda do3
        cmp dwt
        bne drfail              ; (the wrong track: seek again)
        jsr dsync               ; the data block
        bcs drfail
        ldy #0                  ; 325 GCR bytes, as they come
-       bvc -
        clv
        lda $1c01
        sta $0301,y
        iny
        cpy #255
        bne -
        ldy #0
-       bvc -
        clv
        lda $1c01
        sta $0400,y
        iny
        cpy #70
        bne -
        jsr ddec                ; decode, check
        bcs drfail
        rts
drnext  dec dhc
        bne dr2
drfail  lda #0                  ; seek again next time (the head may be off)
        sta dtrk
        dec dtry
        beq +
        jmp dr0
+       sec
        rts

; the data block: 65 groups of 5 GCR bytes to 260 bytes, decoded in place
; (byte n at $0301+n: written behind the group being read), the ID ($07)
; and the checksum (the 256 bytes eor'd) checked: C set on a mismatch
ddec    ldy #0                  ; groups 0-50 from $0301 (X: 0, 5 .. 250)
        lda #$01
        ldx #$03
        jsr dbase
        ldx #0
-       jsr dgrp
        cpx #255
        bne -
        lda #$00                ; groups 51-63 from $0400
        ldx #$04
        jsr dbase
        ldx #0
-       jsr dgrp
        cpx #65
        bne -
        jsr dload               ; group 64: the last byte and the checksum
        jsr dgcr
        lda do0
        sta $0401
        lda $0301               ; the block ID
        cmp #$07
        bne +
        ldx #0
        txa
-       eor $0302,x
        inx
        bne -
        cmp do1
        bne +
        clc
        rts
+       sec
        rts

; a group: load its 5 bytes (from the base at X), decode, put 4 at
; $0301,y on; X += 5
dgrp    jsr dload
        stx dsx
        jsr dgcr
        ldx #0
-       lda do0,x
        sta $0301,y
        iny
        inx
        cpx #4
        bne -
        lda dsx
        clc
        adc #5
        tax
        rts

; the 5 bytes at the base + X to db0-4
dload
dl0     lda $0301,x
        sta db0
dl1     lda $0302,x
        sta db1
dl2     lda $0303,x
        sta db2
dl3     lda $0304,x
        sta db3
dl4     lda $0305,x
        sta db4
        rts

; dload's base: A low, X high (into its five lda's, 6 bytes apart; no
; base here crosses a page)
dbase   sta dt
        stx dsx
        ldx #0
-       lda dt
        sta dl0+1,x
        lda dsx
        sta dl0+2,x
        inc dt
        txa
        clc
        adc #6
        tax
        cpx #30
        bne -
        rts

; 5 GCR bytes db0-4 -> 4 bytes do0-3 (8 quintets: dgh high nibbles, dgl low)
dgcr    lda db0                 ; q0 = b0 >> 3
        lsr a
        lsr a
        lsr a
        tax
        lda dgh,x
        sta do0
        lda db0                 ; q1 = (b0 & 7) << 2 | b1 >> 6
        and #7
        asl a
        asl a
        sta dt
        lda db1
        asl a
        rol a
        rol a
        and #3
        ora dt
        tax
        lda dgl,x
        ora do0
        sta do0
        lda db1                 ; q2 = (b1 >> 1) & 31
        lsr a
        and #31
        tax
        lda dgh,x
        sta do1
        lda db1                 ; q3 = (b1 & 1) << 4 | b2 >> 4
        and #1
        asl a
        asl a
        asl a
        asl a
        sta dt
        lda db2
        lsr a
        lsr a
        lsr a
        lsr a
        ora dt
        tax
        lda dgl,x
        ora do1
        sta do1
        lda db3                 ; q4 = (b2 & 15) << 1 | b3 >> 7
        asl a
        lda db2
        and #15
        rol a
        tax
        lda dgh,x
        sta do2
        lda db3                 ; q5 = (b3 >> 2) & 31
        lsr a
        lsr a
        and #31
        tax
        lda dgl,x
        ora do2
        sta do2
        lda db3                 ; q6 = (b3 & 3) << 3 | b4 >> 5
        and #3
        asl a
        asl a
        asl a
        sta dt
        lda db4
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        ora dt
        tax
        lda dgh,x
        sta do3
        lda db4                 ; q7 = b4 & 31
        and #31
        tax
        lda dgl,x
        ora do3
        sta do3
        rts

dcode_top
        .here
dcode_end
        .cerror dcode_top > $0800, "the drive code must end by $07ff"

; the drive's tables, the file name, the variables and two routines: $0146
; on (the stack page above the DOS's stack, $0100-$0145; $01ba up is its
; GCR overflow, used only by its own data reads: Initialize's at the end)
DDATA   = $0146
ddata
        .logical DDATA
DPAIR   = [$00, $08, $02, $0a]  ; a pair (DATA bit 1, CLK bit 0) -> $1800
dta     .byte DPAIR[range(16) & 3] | $10        ; a nibble's low pair, ATNA 1
dtb     .byte DPAIR[range(16) >> 2]             ; its high pair, ATNA 0
; GCR: nibble n is written as the quintet [$0a, $0b, $12, $13, $0e, $0f, $16, $17,
; $09, $19, $1a, $1b, $0d, $1d, $1e, $15][n]; the tables turn quintets back
dgh     .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $80, $00, $10, $00, $c0, $40, $50
        .byte $00, $00, $20, $30, $00, $f0, $60, $70, $00, $90, $a0, $b0, $00, $d0, $e0, $00
dgl     .byte $00, $00, $00, $00, $00, $00, $00, $00, $00, $08, $00, $01, $00, $0c, $04, $05
        .byte $00, $00, $02, $03, $00, $0f, $06, $07, $00, $09, $0a, $0b, $00, $0d, $0e, $00
dname   .text CB_NAME
        .fill 16 - len(CB_NAME), $a0
dent0   .byte 0
dn      .byte 0
dtrk    .byte 0                 ; the track the head is on (0: not known)
dwt     .byte 0                 ; the sector wanted: track, sector
dws     .byte 0
dtry    .byte 0
dhc     .byte 0
dsx     .byte 0
dt      .byte 0
db0     .byte 0
db1     .byte 0
db2     .byte 0
db3     .byte 0
db4     .byte 0
do0     .byte 0
do1     .byte 0
do2     .byte 0
do3     .byte 0
dv      .fill 4
dacc    .byte 0

; the motor up to speed: ~0.6 s (it was off while idle)
dspin   ldx #0
        ldy #0
-       nop
        dex
        bne -
        dey
        bne -
        rts

; wait for a SYNC (bit 7 of $1c00 low): C set after ~0.3 s without one
dsync   ldx #0
        ldy #0
-       lda $1c00
        bpl +
        dex
        bne -
        dey
        bne -
        sec
        rts
+       lda $1c01               ; (the latch cleared)
        clv
        clc
        rts

; the block's end: the C64's extra edge (ATN pulled), then busy: DATA low
; (ATNA 1 matches the pulled ATN; once let go the 1541 pulls DATA itself)
dbusy
-       bit $1800
        bpl -
        lda #$12
        sta $1800
        rts

ddata_top
        .here
ddata_end
        .cerror ddata_top > $0200, "the drive's second piece must end by $01ff"
cb_end
        .cerror cb_end - CB > $800, "CatBoot must fit $c000-$c7ff"
