; ------------------------------------------------------------------ sequencer
; 16 steps (16ths) a bar; a song chains up to 16 bars, each one of four
; pattern slots (A-D) holding a bar for each cat. Run once a frame before sfx.
; A step byte, 0 = nothing:
;   drum cat (voice 3):   drum role 1..14 (styles.py ROLES: BD BM SN BP CP RS
;                         CH OH SH RD GH DU SK DR); the style's kit maps it to
;                         a sound (kitlo/kithi + style*14 + role-1)
;   bass cat (voice 1):   bits 0-4 note (13 = the style's bass root, semitones),
;                         bits 5-6 length - 1 in steps, bit 7 slide up from a semitone below
;   singer cat (voice 2): bits 0-4 scale degree + 1 (degtab), bits 5-6 meow kind
; Swing: even steps last tempo + swing frames, odd ones tempo - swing.
; The singer's dub echoes (title.py): repeats of the meow body every edframes,
; darker and quieter; mono, so only the ones that end before the next meow.
; With a second SID (sid2.asm) they play there instead, from the history of
; the singer's steps (echo2step), so they overlap the next meow like a tape
; delay; and the harmony meow (harmony scale degrees up) sings with the
; singer on SID 2's voice 2.
;
; The song block (saved to disk as it is, packed: disk.asm):
;   song+0 style (low nibble) | mode (high), +1 tempo, +2 swing (low) |
;   bass transpose (high, signed), +3 esteps (echo steps, 0 = off) in
;   the low nibble and the singer's transpose (signed, scale degrees) in the high,
;   +4 chainlen (1-16), +5 chain[16] (slot 0-3), +21 pats: slot s, cat c at
;   song+21 + s*48 + c*16.

step     = $82            ; the step playing
stepcnt  = $83            ; frames left in it
tempo    = $84            ; frames a step (a copy of song+1)
swing    = $85
bassroot = $86            ; semitone of bass note 13
blen     = $87            ; steps the bass note still holds
echo_n   = $88            ; echoes still to come
echo_t   = $89            ; frames to the next
echo_i   = $8a
echo_k   = $8b            ; the meow kind they repeat
edframes = $8c            ; frames between echoes (255: off)
sl       = $8d            ; vstart: script
sh       = $8e
stmp     = $8f
sdist    = $90
cathit   = $91            ; 3 bytes: a cat that played, with what (the step byte)
binst    = $94            ; the style's bass instrument * 2
esteps   = $95            ; echo delay in steps (a copy of song+3)
bar      = $96            ; the bar of the chain playing
pp       = $97            ; 2 bytes: its pattern slot
np       = $99            ; 2 bytes: the next bar's slot (the meow looks ahead)
echoev   = $9b            ; an echo just started (the screen's ear flick)

SONGLEN  = 213
STYLEN   = 246            ; a style: tempo swing bassroot echo binst degtab[32]
                          ; chainlen chain[16] pats[192]

; X = style: its preset song (patterns, chain, tempo...) into the song
; block, then play it from the top
seq_load
        stx song
        lda stylo,x
        sta sl
        lda styhi,x
        sta sh
        ldy #0
        lda (sl),y
        sta song+1              ; tempo
        iny
        lda (sl),y
        sta song+2              ; swing
        ldy #3
        lda (sl),y
        sta song+3              ; echo
        lda harmtab,x           ; the style's harmony (SID 2)
        sta harmony
        ldy #37
        ldx #4
-       lda (sl),y              ; chainlen, chain, pats
        sta song,x
        iny
        inx
        cpx #SONGLEN
        bne -
        lda song                ; the sound settings: the style's (stytweak,
        and #$0f                ; 16 bytes a style)
        asl a
        asl a
        asl a
        asl a
        tax
        ldy #0
-       lda stytweak,x
        sta tweaks,y
        inx
        iny
        cpy #TWLEN
        bne -
        ; fall through

; play the song block: the style's sounds and scale, its tempo; from the top
seq_apply
        lda song                ; low nibble: the style, high: the mode
        and #$0f
        sta cstyle
        lda song
        lsr a
        lsr a
        lsr a
        lsr a
        sta smode
        lda song+2              ; high nibble of the swing byte: the bass's
        lsr a                   ; transpose (signed, scale degrees)
        lsr a
        lsr a
        lsr a
        cmp #8
        bcc +
        ora #$f0
+       sta btransp
        ldx cstyle
        lda stylo,x
        sta sl
        lda styhi,x
        sta sh
        ldy #2
        lda (sl),y
        sta bassroot
        ldy #4
        lda (sl),y              ; bass instrument: index of its plain/slide pair
        asl a
        sta binst
        iny
        ldx #0
-       lda (sl),y              ; degtab
        sta degtab,x
        iny
        inx
        cpx #32
        bne -
        jsr modescale           ; the mode: the singer's scale and the mask
        lda song+1
        sta tempo
        lda song+2
        and #$0f
        sta swing
        lda song+3              ; low nibble: echo steps
        and #$0f
        sta esteps
        lda song+3              ; high nibble: the singer's transpose (signed)
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #8
        bcc +
        ora #$f0
+       sta transp
        jsr seq_retempo
        lda #0
        sta echo_n
        sta blen
        sta echoev
        sta hpos
        sta bpos
        sta dblen
        ldx #31                 ; no echoes from before
-       sta hist,x
        sta bhist,x
        dex
        bpl -
        lda song+4
        sec
        sbc #1
        sta bar                 ; the last bar, so the first tick starts bar 0
        lda #15                 ; ...at step 0
        sta step
        lda #1
        sta stepcnt
        jmp setbar

; after a tempo or echo change: the echo delay in frames follows it
seq_retempo
        lda #255                ; off: no echo ever fits
        ldx esteps
        beq +
        lda #0
-       clc
        adc tempo
        dex
        bne -
+       sta edframes
        rts

; bar = the next bar of the chain; pp = its slot, np = the one after
nextbar ldx bar
        inx
        cpx song+4
        bcc +
        ldx #0
+       stx bar
setbar  ldx bar
        lda song+5,x
        jsr slotptr
        sta pp
        sty pp+1
        ldx bar
        inx
        cpx song+4
        bcc +
        ldx #0
+       lda song+5,x
        jsr slotptr
        sta np
        sty np+1
        rts

; A = slot -> A/Y = its address (song+21 + slot*48)
slotptr asl a
        asl a
        asl a
        asl a                   ; *16
        sta stmp
        asl a                   ; *32
        clc
        adc stmp                ; *48
        clc
        adc #<(song+21)
        pha
        lda #>(song+21)
        adc #0
        tay
        pla
        rts

seq_tick
        lda #0
        sta echoev
        jsr echoes
        dec stepcnt
        beq +
        rts
+       lda step
        clc
        adc #1
        and #15
        sta step
        bne +
        jsr nextbar             ; a new bar
+       lda step
        lsr a                   ; C = odd
        lda tempo
        bcs +
        clc
        adc swing
        bne ++
+       sec
        sbc swing
+       sta stepcnt
        lda sid2+1              ; SID 2: this step's echoes
        beq +
        lda mute+2
        bne +
        jsr echo2step
+
        ldy step                ; drum cat (not when muted)
        lda (pp),y
        beq +
        ldx mute
        bne +
        jsr trig_drum
+       lda step                ; bass cat
        ora #16
        tay
        lda (pp),y
        bne stbass
        lda blen                ; a rest: the note ends when its length does
        beq stb0
        dec blen
        bne stb0
        jsr bass_off
        jmp stb0
stbass  ldx mute+1
        bne stb0
        jsr trig_bass
        lda cathit+1            ; (the step byte it played)
        .byte $2c
stb0    lda #0
        jsr bdelay              ; into the history; the delay's echo
stsing  lda step                ; singer cat
        ora #32
        tay
        lda (pp),y
        bne +
        rts
+       ldx mute+2
        beq +
        rts
+       ldx #1                  ; plan echoes (looks ahead)
        jmp trig_sing

; A = the bass step byte this step played (0: none): into bhist; then
; the bass delay (btweak's high nibble: off, 1 2 3 4 6 8 12 steps) plays
; the one that many steps ago on SID 2's third voice (sfx.asm: sustain 5
; lower), for as long as it lasted
bdelay  sta dbyte
        ldy bpos
        iny
        tya
        and #31
        sta bpos
        tay
        lda dbyte
        sta bhist,y
        lda dblen               ; the delayed note's length runs out
        beq +
        dec dblen
        bne +
        lda ctl+5
        and #$fe
        sta ctl+5
        ldy sidoff+5
        sta $d404,y
+       lda sid2+1
        beq bd9
        lda btweak
        lsr a
        lsr a
        lsr a
        lsr a
        beq bd9
        tax
        lda bpos
        sec
        sbc dsteps,x
        and #31
        tay
        lda bhist,y
        beq bd9
        sta dbyte
        jsr bassnote
        sta vnote+5
        lda dbyte
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        clc
        adc #1
        sta dblen
        ldy binst
        lda dbyte
        bpl +
        iny
+       lda basslo,y
        sta sl
        lda basshi,y
        sta sh
        lda tflags              ; Dub filter: the repeat sweeps SID 2's
        and #4                  ; filter from bright to dark (sfx.asm
        beq +                   ; dubflt)
        lda #DFPEAK
        sta dfenv
+       ldx #5
        jmp vstart
bd9     rts
dsteps  .byte 0, 1, 2, 3, 4, 6, 8, 12
bpos    .byte 0
dblen   .byte 0
dbyte   .byte 0
bhist   .fill 32

bass_off
        lda ctl
        and #$fe
        sta ctl
        sta $d404
        rts

; A = drum step byte (a role 1..14): the style's sound for it on voice 3
trig_drum
        sta cathit
        cmp #3                  ; BD, BM: the bass ducks (sfx.asm scduck)
        bcs +
        ldx #SCLEN
        stx scdk
+
        ldx cstyle
        clc
        adc kitrow,x            ; style*14 - 1
        tay
        lda kitlo,y
        sta sl
        lda kithi,y
        sta sh
        ldx #2
        jmp vstart

; A = bass step byte: the note on voice 1
trig_bass
        sta cathit+1
        sta stmp
        lda tflags              ; Meowize + Res boost: the note opens the
        and #3                  ; filter (sfx.asm squelch)
        cmp #3
        bne +
        lda #BFPEAK
        sta bfenv
+       lda stmp
        jsr bassnote
        sta vnote
        lda stmp
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        clc
        adc #1
        sta blen
        ldy binst               ; plain or slide
        lda stmp
        bpl +
        iny
+       lda basslo,y
        sta sl
        lda basshi,y
        sta sh
        ldx #0
        jmp vstart

;  --- the mode changer and the bass transpose
; mode 0: the style's own scale; 1-7: major, minor, dorian, phrygian,
; mixolydian, lydian, blues on the style's tonic (styles.py MODES). Notes
; are mapped as they play (qdelta: by scale degree), nothing stored changes.

; the style's degtab again, through the smode (after a smode change)
loadscale
        ldx cstyle
        lda stylo,x
        sta sl
        lda styhi,x
        sta sh
        ldy #5
        ldx #0
-       lda (sl),y
        sta degtab,x
        iny
        inx
        cpx #32
        bne -
        ; fall through

; the singer's degtab through the smode; smask = the scale's pitch classes
modescale
        ldx cstyle
        lda smode
        bne +
        lda inscl,x             ; the style's own: as it is
        sta smask
        lda insch,x
        sta smask+1
        rts
+       tax
        lda modeml,x
        sta smask
        lda modemh,x
        sta smask+1
        lda smode                ; smode * 12: its qdelta row
        asl a
        asl a
        sta stmp
        asl a
        clc
        adc stmp
        sta mrow
        ldx cstyle
        lda stroot,x
        sta mroot
        ldx #31
-       lda degtab,x
        jsr quant
        sta degtab,x
        dex
        bpl -
        rts

; A = semitone, mroot/mrow set: A mapped into the smode; keeps X
quant   sta stmp
        sec
        sbc mroot
        clc
        adc #120                ; (positive, a multiple of 12 apart)
-       cmp #12
        bcc +
        sbc #12
        bcs -
+       tay                     ; the pitch class
        tya
        clc
        adc mrow
        tay
        lda qdelta,y
        clc
        adc stmp
        rts

; A = bass step byte -> A = the semitone it plays: through the smode, then
; btransp scale degrees up or down
bassnote
        and #$1f
        clc
        adc bassroot
        sec
        sbc #13
        sta bnt
        lda smode
        beq +
        asl a
        asl a
        sta mrow
        asl a
        clc
        adc mrow
        sta mrow
        lda bassroot
        sta mroot
        lda bnt
        jsr quant
        sta bnt
+       lda btransp
        beq bn9
        bmi bndown
        sta bnc
-       inc bnt                 ; up: to the next note in the scale, btransp times
        jsr bnin
        beq -
        dec bnc
        bne -
        beq bn9
bndown  eor #$ff
        clc
        adc #1
        sta bnc
-       dec bnt
        jsr bnin
        beq -
        dec bnc
        bne -
bn9     lda bnt
        rts
; Z clear when bnt is in smask (pitch class relative to the bass root)
bnin    lda bnt
        sec
        sbc bassroot
        clc
        adc #120
-       cmp #12
        bcc +
        sbc #12
        bcs -
+       tay
        cpy #8
        bcs +
        lda smask
        and bit8s,y
        rts
+       lda smask+1
        and bit8s-8,y
        rts
bit8s   .byte 1, 2, 4, 8, 16, 32, 64, 128

; X = voice, sl/sh = script: start it now (this frame's sfx runs it)
vstart  cpx #3                  ; on SID 2 the newest owns the filter (not
        bcc +                   ; the bass delay: it isn't filtered)
        cpx #5
        beq +
        stx cut2own
+       lda sl
        sta sptrl,x
        lda sh
        .if CHECKPTR
        cmp #$88
        bcc ckp3
ckjam3  .byte $02
ckp3    lda sh
        .endif
        sta sptrh,x
        lda #0
        sta swait,x
        sta pslc,x
        sta wslc,x
        sta cslc,x
        sta chop,x
        sta gslc,x
        sta reth,x              ; no stale return from a cut-off echo
        rts

; A = singer step byte, X = 1: plan echoes from the song (0: an audition,
; no echoes). Sets the contour, starts the meow. SID 2: the harmony too,
; and the echoes come from the step history instead.
trig_sing
        stx sdist               ; (the flag, for now)
        sta cathit+2
        sta hstep
        lda harmony             ; SID 2's harmony meow
        beq th1
        ldx sid2+1
        beq th1
        sta stmp
        lda hstep
        and #$1f
        clc
        adc stmp
        cmp #27                 ; its peak must stay in degtab
        bcs th1
        lda hstep
        ldy harmony
        jsr contour
        ldy #2
        jsr cstore
        lda harmlo,x
        sta sl
        lda harmhi,x
        sta sh
        ldx #4
        jsr vstart
th1     lda hstep
        ldy #0
        jsr contour
        stx echo_k
        ldy #0
        jsr cstore
        lda meowlo,x            ; start it
        sta sl
        lda meowhi,x
        sta sh
        ldx #1
        jsr vstart
        lda #0
        sta echo_n
        sta echo_i
        lda sdist
        bne +
        rts
+       lda sid2+1              ; SID 2: into the history, echo2step plays it
        beq +
        ldy hpos
        lda hstep
        sta hist,y
        rts

+       lda step                ; steps to the next meow, into the next bar
        ora #32
        tay
        ldx #0
la      inx
        cpx #16
        beq ldone               ; none for a bar: up to itself again
        iny
        cpy #48
        beq lb0
        lda (pp),y
        beq la
        bne ldone
lb0     ldy #32                 ; on in the next bar's singer row
        bne lbchk
lb      inx
        cpx #16
        beq ldone
        iny
lbchk   lda (np),y
        beq lb
ldone   lda #255                ; no meow for a bar: every echo fits
        cpx #16
        beq lfar
        lda #0                  ; in frames, a swing's worth early
-       clc
        adc tempo
        dex
        bne -
        sec
        sbc swing
lfar    sta sdist
        ldx echo_k
        lda edframes
        sta echo_t
        cmp mlen,x              ; an echo sooner than the meow ends would
        bcc +                   ; cut it before it lands: none then
        clc
        adc mlen,x              ; echo 1 fits?
        bcs +
        cmp sdist
        beq e1
        bcs +
e1      inc echo_n
        clc                     ; echo 2?
        adc edframes
        bcs +
        cmp sdist
        beq e2
        bcs +
e2      inc echo_n
+       rts

; A = singer step byte, Y = scale degrees up: its meow contour into zero
; page (m0l..ms1); X = the meow kind. Uses mw, stmp
contour sty mw
        sta stmp
        and #$1f
        clc
        adc mw
        adc #4-1                ; degtab index of the target: degree + 4
        clc
        adc transp              ; the singer's transpose (scale degrees)
        bpl +
        lda #2
+       cmp #2                  ; start and peak must stay in degtab
        bcs +
        lda #2
+       cmp #30
        bcc +
        lda #29
+       sta mw
        lda stmp
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        sta ckind
        tax
        ldy mw                  ; P1: the target
        lda degtab,y
        sta m1l
        clc
        lda mw
        adc kd0,x
        tay
        lda degtab,y            ; start
        sta m0l
        clc
        lda mw
        adc kdp,x
        tay
        lda degtab,y            ; peak (semitones in stmp)
        sta stmp
        sec                     ; D0 = peak - start
        sbc m0l
        jsr dmag
        sta md0
        stx ms0
        lda m1l                 ; D1 = landing - peak
        sec
        sbc stmp
        jsr dmag
        sta md1
        stx ms1
        lda m0l                 ; P0 and P1 * 16
        ldx #0
        jsr x16
        sta m0l
        stx m0h
        lda m1l
        ldx #0
        jsr x16
        sta m1l
        stx m1h
        ldx ckind               ; the kind's sound settings (tweaks): Vowel
        lda twvowel,x           ; and Tone for the frames (cstore keeps them
        sta mvow                ; with the contour), Bend now
        lda twtone,x
        sta mtone
        lda twbend,x
        cmp #8
        beq cbend9              ; 8: as made (bit-exact)
        sta cbidx
        lda md0                 ; the swoop as made
        sta cb_d0
        lda md1
        sta cb_d1
        lda m0l
        sta cb_p0
        lda m0h
        sta cb_p0+1
cbtry   ldy cbidx               ; the swoop's two halves * bendf / 8...
        lda bendf,y
        sta s4b
        lda cb_d0
        jsr scl8
        sta md0
        lda cb_d1
        jsr scl8
        sta md1
        lda m1l                 ; ...and the start from the landing, so it
        sta m0l                 ; still lands on its note: P0 = P1 - D1 - D0
        lda m1h
        sta m0h
        lda md1
        ldx ms1
        jsr p0less
        lda m0h                 ; (the peak: inside the pitch table?)
        jsr cbchk
        bcs cbless
        lda md0
        ldx ms0
        jsr p0less
        lda m0h
        jsr cbchk
        bcc cbend9
cbless  lda cbidx               ; too wide for the pitch table: a step toward
        cmp #9                  ; as made, and again
        bcc cbold
        dec cbidx
        lda cbidx
        cmp #8
        bne cbtry
cbold   lda cb_d0               ; the swoop as made
        sta md0
        lda cb_d1
        sta md1
        lda cb_p0
        sta m0l
        lda cb_p0+1
        sta m0h
cbend9  ldx ckind
        rts

; m0 -= the signed distance A (magnitude, 1/16 semitones), X its sign (0
; up, $ff down)
p0less  cpx #0
        bne +
        sta stmp
        lda m0l
        sec
        sbc stmp
        sta m0l
        lda m0h
        sbc #0
        sta m0h
        rts
+       clc
        adc m0l
        sta m0l
        lda m0h
        adc #0
        sta m0h
        rts

; A = m0h: C set when m0 is outside 0 - $5df (the tables: 95 semitones,
; and p2f reads the next one up)
cbchk   cmp #$05
        bcc +                   ; < $500 (and not negative: bit 7 clear)
        bne ++                  ; $6xx up, or negative
        lda m0l
        cmp #$e0
        rts
+       clc
        rts
+       sec
        rts

; A * s4b / 8 (s4b 0-63), at most 255; uses Y, keeps X
scl8    sta s4a
        lda #0
        sta s4a+1
        sta s4p
        sta s4p+1
        lda s4b
        sta s4t
        ldy #6
-       lsr s4t                 ; shift and add
        bcc +
        clc
        lda s4p
        adc s4a
        sta s4p
        lda s4p+1
        adc s4a+1
        sta s4p+1
+       asl s4a
        rol s4a+1
        dey
        bne -
        lda s4p+1               ; / 8
        lsr a
        ror s4p
        lsr a
        ror s4p
        lsr a
        ror s4p
        ora #0
        bne +
        lda s4p
        rts
+       lda #255
        rts

; Bend and Vowel, index 0-16 (8 = as made) -> factor in eighths: fine near
; as made, wider at the ends (Bend up to 4 times the swoop, Vowel 3 times
; the opening)
bendf   .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 20, 24, 28, 32
vowf    .byte 0, 1, 2, 3, 4, 5, 6, 7, 8, 10, 12, 14, 16, 18, 20, 22, 24

s4a      .word 0
s4p      .word 0
s4t      .byte 0
s4b      .byte 0
cbidx    .byte 0
mvow     .byte 8          ; the Vowel, Tone of the last contour (cstore keeps
mtone    .byte 8          ; them)
cb_d0    .byte 0
cb_d1    .byte 0
cb_p0    .word 0

; SID 2, at each step: the echo of the meow esteps steps ago, or else the
; second echo of the one 2 * esteps ago (hist: the singer's last 32 steps),
; on SID 2's voice 1 with its own filter. Nothing waits for the next meow.
echo2step
        lda hpos
        clc
        adc #1
        and #31
        sta hpos
        tay
        lda #0
        sta hist,y              ; this step: no meow yet
        lda esteps
        beq e2none
        tya
        sec
        sbc esteps
        and #31
        tay
        ldx #0
        lda hist,y
        bne e2go
        tya
        sec
        sbc esteps
        and #31
        tay
        ldx #1
        lda hist,y
        beq e2none
e2go    stx e2i
        ldy #0
        jsr contour
        ldy #1
        jsr cstore
        txa
        asl a
        ora e2i
        tay
        lda pre2lo,y
        sta sl
        lda pre2hi,y
        sta sh
        ldx e2i
        lda edark,x             ; darker each time
        sta cdark2
        ldx #3
        jsr vstart
        lda #1
        sta echoev
e2none  rts

; A = signed semitones -> A = |A| * 16, X = sign (0 / $ff)
dmag    ldx #0
        ora #0                  ; (the sign, after the ldx)
        bpl +
        eor #$ff
        clc
        adc #1
        ldx #$ff
+       asl a
        asl a
        asl a
        asl a
        rts

; A (semitones) -> A lo, X hi of A * 16
x16     stx stmp
        .rept 4
        asl a
        rol stmp
        .next
        ldx stmp
        rts

echoes  lda echo_n
        beq +
        dec echo_t
        bne +
        lda edframes
        sta echo_t
        dec echo_n
        lda echo_k
        asl a
        ora echo_i
        tay
        lda prelo,y
        sta sl
        lda prehi,y
        sta sh
        ldx #1
        jsr vstart
        inc echo_i
        lda #1
        sta echoev
+       rts

degtab   .fill 32         ; the singer's scale, semitones from C0, degree -4..27
transp   .byte 0          ; the singer's transpose in scale degrees (-7..+7)
btransp  .byte 0          ; the bass's (-7..+7)
cstyle   .byte 0          ; the style (song+0's low nibble)
smode     .byte 0          ; the smode (its high nibble): 0 = the style's own
smask    .word 0          ; the scale's pitch classes (bit = semitone above the tonic)
mrow     .byte 0
mroot    .byte 0
bnt      .byte 0
bnc      .byte 0
harmony  .byte 0          ; SID 2's harmony meow: scale degrees up, 0 = off
mute     .byte 0, 0, 0    ; a cat muted (drums, bass, singer): not played
; the song's sound settings, 16 bytes, saved with it (disk.asm format 4);
; a style sets them (styles.py -> stytweak, 16 bytes a style)
tweaks
twbend   .byte 8, 8, 8, 8     ; per meow kind (mew, meow, ooh, mrr?): Bend,
twvowel  .byte 8, 8, 8, 8     ; Vowel, Tone 0-16, 8 = as made (shown -8..+8)
twtone   .byte 8, 8, 8, 8
twside   .byte 0              ; low nibble: the drums' Sidechain 0 (off) - 8;
                          ; high: the bass's Level 0 (as made) - 8 (quieter)
twtune   .byte 8              ; ...Tune 0-16, 8 = as made (shown -8..+8)
btweak   .byte $00            ; the bass: Delay (high, 0 off - 7, SID 2) and
                          ; Wave (low: 0 the style's, 1 pulse, 2 saw, 3 tri)
tflags   .byte 0              ; bit 0: Meowize (the bass through the meows' filter),
                          ; bit 1: Res boost (that filter's resonance at the top),
                          ; bit 2: Dub filter (the bass delay through SID 2's filter),
                          ; high nibble: the meows' Cat Size 0 (Fat Cat, as made)
                          ; - 3 (Newborn): levels 0 2 6 8 (sfx.asm getlvl)
TWLEN    = * - tweaks
        .cerror TWLEN != 16, "the tweaks block is 16 bytes"
hist     .fill 32         ; SID 2's echoes: the singer's last 32 steps
hpos     .byte 0          ; ...this step's
hstep    .byte 0
ckind    .byte 0
e2i      .byte 0
song     .fill SONGLEN
