; ------------------------------------------------------------------ SID 2
; A second SID (C64 Ultimate / Ultimate 64 UltiSID, a dual-SID board), used
; when present: the singer's dub echoes play on its voice 1 and the harmony
; meow on its voice 2, both through its own filter (sfx.asm voices X = 3, 4;
; seq.asm echo2step and trig_sing). A stock C64 has none and plays as before.
;
; Where: $d420, $d440 ... $d4e0 (the player reaches SID 2 as $d400,y, so
; only page $d4 fits). The C64 Ultimate's usual is $d420 (UltiSID 2).
;
; Detection, the ENV3 test (c64bridge c64://ultimate/multisid): voice 3 of
; the candidate gated (attack 0, sustain 15), two frames later its ENV3
; ($1c) must read $ff while SID 1's $d41c reads 0 (a mirror of SID 1, as
; $d420 is on a stock C64, gates both and reads $ff at both); then with the
; gate off it must fall back to 0 (an empty address reads open bus).
;
;   sid2_init   after sid_detect/sid_init: probes $d420..$d4e0, takes the
;               first SID found (sid2_use) and leaves SID 1 initialised
;               again. About 0.1 s a candidate (0.6 s on a stock C64).
;   sid2_use    A = SID 2's address low byte ($20..$e0): play on it
;   sid2_show   "sid2 d4xx" on the panel's top row (nothing without one),
;               after screen_init
;   harm_toggle the harmony: off, 2 or 4 scale degrees up
;
; sid2 (sfx.asm, a word): 0 = none, else SID 2's address.

s2cnt   .byte 0

sid2_init
        lda #$20
-       sta sid2
        tay
        jsr s2probe
        bcc +
        lda sid2
        clc
        adc #$20
        bne -                   ; to $e0
        sta sid2                ; none: 0, and mono
        jmp sid_init            ; (a mirror got SID 1's voice 3 going)
+       jsr sid_init
        lda sid2
        jmp sid2_use

; Y = candidate - $d400: C clear if a SID of its own answers there
s2probe jsr s1v3off             ; SID 1's voice 3 silent: its ENV3 falls to 0
        lda #0
        sta $d413,y             ; attack 0
        lda #$f0
        sta $d414,y             ; sustain 15, release 0
        lda #$ff
        sta $d40f,y
        lda #$21                ; sawtooth, gate
        sta $d412,y
        jsr s2wait
        lda $d41c,y
        cmp #$ff
        bne s2no
        lda $d41c
        bne s2no                ; SID 1 heard it too: a mirror
        lda #$20                ; gate off
        sta $d412,y
        jsr s2wait
        lda $d41c,y
        bne s2no
        jsr s2v3off
        clc
        rts
s2no    jsr s2v3off
        sec
        rts

s2v3off lda #0
        sta $d412,y
        sta $d413,y
        sta $d414,y
        rts
s1v3off lda #0
        sta $d412
        sta $d413
        sta $d414
        rts

; about two PAL frames; keeps Y
s2wait  lda #32
        sta s2cnt
s2w1    ldx #0
-       dex
        bne -
        dec s2cnt
        bne s2w1
        rts

; A = SID 2's address low byte: its voices, model and registers
sid2_use
        sta sid2
        sta sidoff+3
        sta modoff+4
        clc
        adc #7
        sta sidoff+4
        adc #7
        sta modoff+3
        sta sidoff+5            ; the third: the bass delay
        lda #$d4
        sta sid2+1
        ldy sid2
        jsr s2model
        lda sid2                ; all its registers 0
        clc
        adc #$18
        tay
        lda #0
-       sta $d400,y
        dey
        cpy sid2
        bcs -
        sta cdark2
        ldy sid2
        lda #$1f                ; lowpass, full volume
        sta $d418,y
        lda #$a3                ; resonance 10, filter voices 1 and 2
        ldx sidmodel2
        bne +
        lda #$73                ; (a 6581 squeals: as wroute)
+       sta $d417,y
        lda #3
        sta cut2own
        ldx #3
        lda #$10
        jsr wcut
        lda #5                  ; the player runs voices 0-5
        sta nvoice
        rts

; Y = SID - $d400: sidmodel2, as sid_detect (tri+saw reads back on an 8580)
s2model lda #$08
        sta $d412,y
        lda #0
        sta $d40e,y
        sta s2cnt
        lda #$10
        sta $d40f,y
        lda #$30
        sta $d412,y
        ldx #0
-       lda $d41b,y
        beq +
        inc s2cnt
        bne +
        dec s2cnt               ; (255 at most)
+       dex
        bne -
        lda #0
        sta sidmodel2
        lda s2cnt
        cmp #64
        bcc +
        inc sidmodel2
+       lda #$08
        sta $d412,y
        lda #0
        sta $d412,y
        rts

; the panel's top row, columns 29-37: "sid2 d420" (nothing in mono)
S2ROW   = SCR_SCREEN + (PANEL_TOP + 1) * 40 + 34
sid2_show                       ; "2sid" at the ruler row's right end
        lda sid2+1              ; (the beat LED sits at column 29)
        beq +
        ldx #3
-       lda t_sid2,x
        sta S2ROW,x
        lda #15
        sta S2ROW - SCR_SCREEN + SCR_COLRAM,x
        dex
        bpl -
+       rts
        .enc "screen"
t_sid2  .text "2sid"
        .enc "none"

; the harmony meow (SID 2): off, a third, a fifth (scale degrees 0, 2, 4)
harm_toggle
        lda harmony
        clc
        adc #2
        cmp #5
        bcc +
        lda #0
+       sta harmony
        rts
