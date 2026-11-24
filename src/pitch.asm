; ------------------------------------------------------------------ pitch
; CatSynth's additions to catsim64's SFX player: a voice's pitch in 1/16
; semitones from C0 (ptl/pth), so transposing is an addition and a glide in
; semitones sounds the same on every note. p2f turns it into the SID
; frequency: the semitone's value from ftl/fth plus fraction/16 of the gap
; to the next one (fdl/fdh, linear; under a cent off in between).
; Tables (styles.py): C0..A#7, semitone 0..94.
;
; Meow contour (seq.asm sets it when the singer meows): three points P0
; (start), the peak and P1 (landing), on scale degrees around the target.
; An SX_MF frame gives w: bit 7 clear = on the way up, P0 + D0 * w / 128;
; bit 7 set = coming down, P1 - D1 * u / 128 (u = w & $7f, 0 = landed), so the
; meow ends exactly on its note. D0/D1 are magnitude + sign, in 1/16 semitones.
; The contour lives in zero page (m0l..ms1, 8 bytes) for the voice playing;
; a second SID's voices meow too (the echo of an older meow, the harmony),
; so each has a copy in ctour (slot vslot,x) and SX_MF loads it when the
; zero page holds another (cload). Mono: always slot 0, never loaded.

; zero page
pfrac    = $70            ; p2f: the 1/16 fraction, shifted out
ptmp     = $71            ; p2f: pth, shifted
accl     = $72            ; p2f: gap * fraction
acch     = $73
mcl      = $74            ; p2f: the gap (fdl/fdh); mul7: the multiplicand
mch      = $75
mw       = $76            ; SX_MF: w, mul7's multiplier (seq.asm: scratch)
mlo      = $77            ; mul7: the product's low byte
madv     = $78            ; SX_MF: its length, 3 (SX_MFV: 4)
mvib     = $79            ; SX_MFV: the vibrato (signed 1/16 semitones)
m0l      = $7a            ; P0
m0h      = $7b
m1l      = $7c            ; P1
m1h      = $7d
md0      = $7e            ; |peak - P0|
ms0      = $7f            ; its sign: 0 up, $ff down
md1      = $80            ; |P1 - peak|
ms1      = $81

; pitch of voice X -> flo/fhi and the SID (rofs); keeps X
p2f     lda pth,x
        sta ptmp
        lda ptl,x
        and #$0f
        sta pfrac
        lda ptl,x               ; (pth:ptl) >> 4: the semitone
        lsr ptmp
        ror a
        lsr ptmp
        ror a
        lsr ptmp
        ror a
        lsr ptmp
        ror a
        tay                     ; semitone
        lda ftl,y               ; its frequency
        sta flo,x
        lda fth,y
        sta fhi,x
        lda pfrac
        beq p2fw                ; (on the semitone: as it is)
        asl a                   ; the fraction's 4 bits to the top
        asl a
        asl a
        asl a
        sta pfrac
        lda fdl,y
        sta mcl
        lda fdh,y
        sta mch
        lda #0
        sta acch
        ldy #4                  ; acc = gap * fraction (shift and add)
-       asl a
        rol acch
        asl pfrac
        bcc +
        clc
        adc mcl
        pha
        lda acch
        adc mch
        sta acch
        pla
+       dey
        bne -
        sta accl                ; / 16
        ldy #4
-       lsr acch
        ror accl
        dey
        bne -
        clc                     ; + the semitone's
        lda flo,x
        adc accl
        sta flo,x
        lda fhi,x
        adc acch
        sta fhi,x
p2fw    ldy rofs                ; voice X's registers - $d400
        lda flo,x               ; frequency low, high
        sta $d400,y
        lda fhi,x
        sta $d401,y
        rts

; ptl/pth of voice X = A * 16; keeps X, Y
setsemi sta ptl,x
        lda #0
        sta pth,x
        .rept 4
        asl ptl,x
        rol pth,x
        .next
        rts

; the script commands (sfx.asm sfxrun: X = voice, Y = 1, the first argument)

; SX_NOTE d: the pitch at once to the sequencer's note (vnote) + d semitones
sx_note lda (sp),y
        clc
        adc vnote,x
        jsr setsemi
        jsr p2f
        lda #2
        jmp sxadv

; SX_GLIDE d, n: the pitch moves d (signed 1/16 semitones) a frame for n
; frames, on its own while the script goes on (sfx.asm sfx)
sx_glide
        lda (sp),y
        sta gd,x
        iny
        lda (sp),y
        sta gslc,x
        lda #3
        jmp sxadv

; SX_STOP: the script ends, the note held
sx_stop lda #0                  ; idle, the gate as it is
        sta sp+1
        rts

; SX_MF w, cut / SX_MFV w, cut, v: a frame of the meow contour (see the
; top): the pitch from w, + v vibrato; the cutoff cut through the slot's
; Vowel and Tone and the echo darkening. Then the script waits the frame
; (sp past the command, no sfxrun).
sx_mfv  ldy #3
        lda (sp),y
        sta mvib
        lda #4
        bne mfgo                ; (always)
sx_mf   lda #0
        sta mvib
        lda #3
mfgo    sta madv
        lda vslot,x             ; this voice's contour in zero page?
        cmp cload
        beq +
        jsr cfetch
+       ldy #1
        lda (sp),y
        bmi mfdown
        sta mw                  ; up: P0 + D0 * w / 128
        lda md0
        jsr mul7
        bit ms0
        bpl +
        eor #$ff                ; negative: two's complement, sign in Y
        clc
        adc #1
        ldy #$ff
        bcc ++                  ; (carry: it was 0, so +0)
+       ldy #0
+       clc
        adc m0l
        sta ptl,x
        tya
        adc m0h
        sta pth,x
        jmp mfvib
mfdown  and #$7f                ; down: P1 - D1 * u / 128
        sta mw
        lda md1
        jsr mul7
        bit ms1                 ; P1 - (signed D1 * u)
        bmi +
        eor #$ff                ; D1 up: subtract
        clc
        adc #1
        ldy #$ff
        bcc ++                  ; (carry: it was 0, so +0)
+       ldy #0                  ; D1 down: P1 + |D1| u
+       clc
        adc m1l
        sta ptl,x
        tya
        adc m1h
        sta pth,x
mfvib   lda mvib                ; + the vibrato, its sign extended into Y
        beq +
        ldy #0
        ora #0                  ; (N: its sign, after the ldy)
        bpl vpos
        dey
vpos    clc
        adc ptl,x
        sta ptl,x
        tya
        adc pth,x
        sta pth,x
+       jsr p2f
        ldy #2                  ; the vowel: the cutoff, opened by Vowel
        lda (sp),y              ; (12 + (cut - 12) * vowf / 8), moved by Tone
        sta mfc                 ; ((tone - 8) * 6), darker for the echoes
        ldy vslot,x
        sty mfs
        lda cvow,y
        cmp #8
        beq mfv8                ; (8: as made)
        tay
        lda vowf,y              ; (seq.asm: the factor in eighths, for scl8)
        sta s4b
        lda mfc
        sec
        sbc #12
        bcc mfv8                ; (closed or below: as it is)
        jsr scl8
        clc
        adc #12
        bcc +
        lda #255                ; (at most 255)
+       sta mfc
mfv8    ldy mfs                 ; Tone
        lda ctone,y
        sec
        sbc #8
        beq mfvt                ; (8: as made)
        sta mft                 ; -8..+7, * 6
        asl a
        clc
        adc mft
        asl a                   ; (signed, -48..+42)
        bmi mfdn
        clc                     ; brighter: at most 255
        adc mfc
        bcc +
        lda #255
+       jmp mfvok
mfdn    clc                     ; darker: at least 0
        adc mfc
        bcs mfvok               ; (no borrow: still >= 0)
        lda #0
        jmp mfvok
mfvt    lda mfc
mfvok   jsr dark
        jsr wcut
        lda madv                ; next command, and that's the frame
        clc
        adc sp
        sta sp
        bcc +
        inc sp+1
+       rts

; A = (A * mw) / 128 for mw 0..127; uses Y, mw, mlo
mul7    sta mcl
        lda #0
        ldy #8
-       lsr mw
        bcc +
        clc
        adc mcl
+       ror a
        ror mlo
        dey
        bne -
        asl mlo                 ; (hi:lo) >> 7
        rol a
        rts

cvow    .byte 8, 8, 8       ; each contour slot's Vowel, Tone (cstore)
ctone   .byte 8, 8, 8
mfc     .byte 0             ; SX_MF: the cutoff being worked out
mfs     .byte 0             ; ...the voice's contour slot
mft     .byte 0             ; ...Tone - 8

; A = slot: its contour from ctour into zero page; keeps X
cfetch  sta cload
        asl a
        asl a
        asl a
        tay
        .for i = 0, i < 8, i += 1
        lda ctour+i,y
        sta m0l+i
        .next
        rts

; Y = slot: the contour in zero page into it (it is now the one loaded);
; keeps X
cstore  sty cload
        lda mvow                ; the kind's Vowel and Tone go with its
        sta cvow,y              ; contour
        lda mtone
        sta ctone,y
        tya
        asl a
        asl a
        asl a
        tay
        .for i = 0, i < 8, i += 1
        lda m0l+i
        sta ctour+i,y
        .next
        rts
