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
echo_i   = $8a            ; the next one's number (0, 1: its script)
echo_k   = $8b            ; the meow kind they repeat
edframes = $8c            ; frames between echoes (255: off)
sl       = $8d            ; vstart: script
sh       = $8e
stmp     = $8f            ; scratch
sdist    = $90            ; trig_sing: frames to the next meow
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
                          ; (offsets 0-4, degtab 5, chainlen 37: song+4 on)

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
        ldy #37                 ; the style's chainlen on, to song+4 on
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
        ldy #2                  ; the style's bass root
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
        lda tempo               ; (a swing over tempo - 3, from an older
        sec                     ; file: played at the cap, see setswing)
        sbc #3
        cmp swing
        bcs +
        sta swing
+       lda song+3              ; low nibble: echo steps
        and #$0f
        sta esteps
        lda song+3              ; high nibble: the singer's transpose (signed)
        lsr a
        lsr a
        lsr a
        lsr a
        cmp #8
        bcc +
        ora #$f0                ; (the sign extended)
+       sta transp
        jsr seq_retempo
        lda #0                  ; the bass (and SID 2's bass delay): a note
        jsr vsilent             ; held over a song change is cut, not left
        lda sid2+1              ; droning
        beq +
        lda #5
        jsr vsilent
+       lda route1              ; the song's filter routing (Meowize, Res
                                ; boost, the Dub filter) into the SIDs now
        jsr wroute1
        lda #0
        sta echo_n
        sta cdark
        sta audt                ; (an audition's timer: not on bar 0's bass)
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
-       clc                     ; esteps * tempo
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

; once a frame, before sfx: the mono echoes; when the step's frames run out
; the next step (its length with the swing), its SID 2 echoes, then each
; cat's cell (drums, bass and its delay, singer) unless muted
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
        ora #16                 ; (its row: step + 16)
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
        .byte $2c               ; (bit abs: skip the lda #0)
stb0    lda #0
        jsr bdelay              ; into the history; the delay's echo
stsing  lda step                ; singer cat
        ora #32                 ; (its row: step + 32)
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
        ldy bpos                ; bpos one on (32 steps round)
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
        and #$fe                ; gate off: its release
        sta ctl+5
        ldy sidoff+5
        sta $d404,y
+       lda sid2+1
        beq bd9                 ; (mono: no delay)
        lda btweak
        lsr a
        lsr a
        lsr a
        lsr a
        beq bd9                 ; (Delay off)
        tax
        lda bpos                ; the step byte that many steps ago
        sec
        sbc dsteps,x
        and #31
        tay
        lda bhist,y
        beq bd9                 ; (a rest then)
        sta dbyte
        jsr bassnote
        sta vnote+5
        lda dbyte               ; bits 5-6: its length - 1, in steps
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        clc
        adc #1
        sta dblen
        ldy binst               ; bit 7: the slide instrument, else plain
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
dsteps  .byte 0, 1, 2, 3, 4, 6, 8, 12   ; Delay 0-7 -> steps back (0: off)
bpos    .byte 0                 ; bhist's newest
dblen   .byte 0                 ; steps the delayed note still holds
dbyte   .byte 0                 ; a bass step byte
bhist   .fill 32                ; the bass's last 32 step bytes (0: none)

; the bass note ends: voice 1's gate off, its release runs
bass_off
        lda ctl
        and #$fe
        sta ctl
        sta $d404
        rts

; A = drum step byte (a role 1..14): the style's sound for it on voice 3
trig_drum
        sta cathit
        jsr pulse_hit           ; the border's beat pulse (ui.asm)
        tax                     ; a kick (BD, BM, and CP, DR: each kit's
        lda rkick,x             ; clap and drop have a kick in them): the
        beq +                   ; bass ducks (sfx.asm scduck)
        ldx #SCLEN
        stx scdk
+       lda cathit
        cmp #13                 ; SK: the skank strums on the song's root,
        bne +                   ; two octaves over the bass's (SX_NOTE)
        lda bassroot
        clc
        adc #24
        sta vnote+2
        lda cathit
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
        lda stmp                ; bits 5-6: its length - 1, in steps
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
        .if LEGATO
        lda ctl                 ; a slide while the last note still sounds
        lsr a                   ; (gate on, its script done: held): no
        bcc tbsl                ; restart, the pitch glides there from
        lda sptrh               ; where it is, as a 303's slide
        bne tbsl
        jmp legato
tbsl
        .endif
        iny
+       lda basslo,y
        sta sl
        lda basshi,y
        sta sh
        ldx #0
        jmp vstart

        .if LEGATO
; the bass (voice 0) glides from its pitch now to vnote in 4 frames: the
; step a quarter of the way (1/16 semitones, signed), the start moved by
; under a quarter so it lands on the note exactly
legato  lda ptl                 ; where it sounds now
        sta lgc
        lda pth
        sta lgc+1
        lda vnote               ; the target * 16
        ldx #0
        jsr setsemi
        lda ptl
        sta lgt
        lda pth
        sta lgt+1
        sec                     ; the distance
        lda lgt
        sbc lgc
        sta lgd
        lda lgt+1
        sbc lgc+1
        sta lgd+1
        ldy #2                  ; / 4, signed (at most 31 semitones: the
-       lda lgd+1               ; step fits a byte; lgd+1 its sign then)
        cmp #$80
        ror lgd+1
        ror lgd
        dey
        bne -
        lda lgd
        sta gd                  ; the step a frame
        asl lgd                 ; * 4: the start = target - 4 * step
        rol lgd+1
        asl lgd
        rol lgd+1
        sec
        lda lgt
        sbc lgd
        sta ptl
        lda lgt+1
        sbc lgd+1
        sta pth
        lda #4
        sta gslc
        rts
lgc     .word 0                 ; legato: the pitch before
lgt     .word 0                 ; legato: the target
lgd     .word 0                 ; ...a step, 4 steps
        .endif

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
        tay
        lda mod12,y             ; the pitch class (a table: the loop cost up
        clc                     ; to ~100 cycles a note)
        adc mrow
        tay
        lda qdelta,y            ; (signed semitones to the mode's note)
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
        sbc #13                 ; (note 13: the root)
        sta bnt
        lda smode
        beq +
        asl a                   ; mrow = smode * 12
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
        beq bn9                 ; (always)
bndown  eor #$ff                ; down: as many the other way
        clc
        adc #1
        sta bnc
-       dec bnt
        jsr bnin
        beq -
        dec bnc
        bne -
bn9     lda bnt                 ; under the lowest note (a transpose down
-       cmp #3                  ; from the bottom octave, or wrapped below
        bcc +                   ; 0): an octave up, so it never wraps to a
        cmp #$c0                ; high note
        bcc ++
+       clc
        adc #12
        sta bnt
        bcc -                   ; (always)
+       rts
; Z clear when bnt is in smask (pitch class relative to the bass root)
bnin    lda bnt
        sec
        sbc bassroot
        clc
        adc #120
        tay
        lda mod12,y             ; the pitch class: bit Y of smask
        tay
        cpy #8
        bcs +
        lda smask
        and bit8s,y
        rts
+       lda smask+1
        and bit8s-8,y
        rts
bit8s   .byte 1, 2, 4, 8, 16, 32, 64, 128   ; bit n's mask, indexed by n
mod12   .byte range(256) % 12   ; n mod 12, for n 0..255

; X = voice, sl/sh = script: start it now (this frame's sfx runs it)
vstart  cpx #3                  ; on SID 2 the newest owns the filter (not
        bcc +                   ; the bass delay: it isn't filtered)
        cpx #5
        beq +
        stx cut2own
+       lda sl
        sta sptrl,x
        lda sh
        sta sptrh,x
        lda #0
        sta swait,x
        sta wslc,x
        sta gslc,x
        sta reth,x              ; no stale return from a cut-off echo
        rts

harmd   .byte 0                 ; trig_sing: the harmony's degrees up
mgap    .byte 0                 ; trig_sing: frames to the next meow (nextdist)
; by drum role 0-14: 1 for the ones with a kick in them (BD BM CP DR)
rkick   .byte 0, 1, 1, 0, 0, 1, 0, 0, 0, 0, 0, 0, 0, 0, 1

; A = singer step byte, X = 1: plan echoes from the song (0: an audition,
; no echoes). Sets the contour, starts the meow. SID 2: the harmony too,
; and the echoes come from the step history instead.
trig_sing
        stx sdist               ; (the flag, for now)
        sta cathit+2
        sta hstep
        lda #255                ; frames to the next meow (an audition:
        cpx #0                  ; none, all the time it wants)
        beq +
        jsr nextdist
+       sta mgap
        lda harmony             ; SID 2's harmony meow
        beq th1
        ldx sid2+1
        beq th1
        cmp #4                  ; (the "5th": 4 degrees on a 7-note scale,
        bne +                   ; 3 on a pentatonic one, else a 6th or 7th)
        ldx cstyle
        ldy sclen,x
        cpy #6
        bcs +
        lda #3
+       sta harmd
        sta stmp
        lda hstep
        and #$1f
        clc
        adc stmp
        cmp #27                 ; its peak must stay in degtab
        bcs th1
        lda hstep               ; its contour, harmony degrees up (X: kind)
        ldy harmd
        jsr contour
        ldy #2                  ; slot 2: the harmony's
        jsr cstore
        lda harmlo,x            ; the kind's harmony script
        sta sl
        lda harmhi,x
        sta sh
        ldx #4                  ; on SID 2's voice 2
        jsr vstart
th1     lda hstep               ; the singer's own
        ldy #0
        jsr contour
        stx echo_k
        ldy #0                  ; slot 0: the singer's
        jsr cstore
        lda #0                  ; (a mono echo the meow cuts short leaves
        sta cdark               ; no darkness behind)
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
        rts                     ; (an audition: no echoes)
+       lda sid2+1             ; SID 2: into the history, echo2step plays it
        beq +
        ldy hpos
        lda hstep
        sta hist,y
        rts

+       lda mgap                ; (nextdist, at the start)
lfar    sta sdist
        ldx echo_k              ; how many echoes fit before it: 0-2
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

; the frames from this step to the next meow (in this bar or the next; a
; swing's worth early), 255 when none comes for a bar: A
nextdist
        lda step                ; steps to the next meow, into the next bar
        ora #32
        tay
        ldx #0                  ; X = steps ahead, Y = that singer cell
la      inx
        cpx #16
        beq ldone               ; none for a bar: up to itself again
        iny
        cpy #48
        beq lb0
        lda (pp),y
        beq la
        bne ldone               ; (always: found)
lb0     ldy #32                ; on in the next bar's singer row
        bne lbchk               ; (always)
lb      inx
        cpx #16
        beq ldone
        iny
lbchk   lda (np),y
        beq lb
ldone   lda #255                ; no meow for a bar: every echo fits
        .if !ECHOBAR            ; (ECHOBAR: it comes back in 16 steps, so
        cpx #16                 ; only the echoes that end before)
        beq ndfar
        .endif
        lda #0                  ; in frames, a swing's worth early
-       clc
        adc tempo
        dex
        bne -
        sec
        sbc swing
ndfar   rts

        .if MEOWFIT
; A = the Bend index (0-16), X = the meow kind: capped when the next meow
; comes before this one ends (mgap < mlen: it would be cut at the peak, off
; its note): at most mgap * 8 / mlen, a Bend that much flatter, so a cut
; meow ends near its written note (a cut halfway: half the swoop)
bcap    sta bci
        lda mgap
        cmp mlen,x
        bcs bc9                 ; (it fits: as set)
        sta bcv                 ; mgap * 8, 16 bits
        lda #0
        sta bcv+1
        ldy #3
-       asl bcv
        rol bcv+1
        dey
        bne -
        ldy #$ff                ; Y = how many mlen fit in it (0-7)
-       iny
        lda bcv
        sec
        sbc mlen,x
        sta bcv
        bcs -
        dec bcv+1
        bpl -
        cpy bci                 ; the smaller
        bcs bc9
        tya
        rts
bc9     lda bci
        rts
bci     .byte 0
bcv     .word 0
        .endif

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
        lda #2                  ; (below 0: the bottom)
+       cmp #2                  ; start and peak must stay in degtab
        bcs +
        lda #2
+       cmp #30
        bcc +
        lda #29
+       sta mw
        lda stmp                ; bits 5-6: the meow kind
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
        clc                     ; (kd0, kdp: per kind, the start's and the
        lda mw                  ; peak's degrees from the target)
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
        .if MEOWFIT
        jsr bcap                ; (the next meow sooner than this one ends)
        .endif
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
cbless  lda cbidx               ; too wide for the pitch table: halfway
        clc                     ; back toward as made (8), and again (at
        adc #8                  ; most 3 more tries: 16 12 10 9, then as
        lsr a                   ; made; one at a time was up to 8, ~15000
        cmp #9                  ; cycles in a frame)
        bcc cbold
        sta cbidx
        jmp cbtry
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
; up, $ff down); uses stmp
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
; Vowel 0-16 (8 = as made): the cutoff vbase + (the meow's - 12) * vsweep / 8
; through the filter mode vmode: from a closed "uuh" (a steady low cutoff)
; through "ooh" to the meow, then wider, then band-pass: "aah" (~1 kHz) up
; to "eeh" (~2 kHz); quieter, a band-pass keeps less of the pulse. (A 6581's
; filter hardly goes lower than the meow's closed cutoff: there the dark end
; is mostly Tone's pulse width.)
vbase   .byte 6, 7, 8, 9, 10, 11, 12, 12, 12, 12, 14, 18, 22, 30, 32, 38, 44
vsweep  .byte 0, 0, 1, 1, 2, 3, 4, 6, 8, 14, 3, 2, 2, 2, 1, 1, 1
vmode   .byte $10, $10, $10, $10, $10, $10, $10, $10, $10, $10
        .byte $20, $20, $20, $20, $20, $20, $20
; Tone 0-16 (8 = as made): the cutoff * tonef / 8, and the meow's pulse
; width tonepw (a hollow square at the dark end, a thin buzz at the bright)
tonef   .byte 3, 3, 4, 4, 5, 6, 6, 7, 8, 9, 10, 11, 12, 14, 16, 18, 20
tonepw  .word $800, $7c0, $780, $740, $700, $6c0, $680, $640, $600
        .word $560, $4c0, $420, $380, $300, $280, $200, $180

s4a      .word 0          ; scl8: A, shifted up
s4p      .word 0          ; ...the product
s4t      .byte 0          ; ...s4b, shifted out
s4b      .byte 0          ; scl8's factor in eighths (bendf, vsweep, tonef)
cbidx    .byte 0          ; contour: the Bend index being tried
mvow     .byte 8          ; the Vowel, Tone of the last contour (cstore keeps
mtone    .byte 8          ; them)
cb_d0    .byte 0          ; contour: the swoop as made, D0, D1, P0
cb_d1    .byte 0
cb_p0    .word 0

; SID 2, at each step: the echo of the meow esteps steps ago, or else the
; second echo of the one 2 * esteps ago (hist: the singer's last 32 steps),
; on SID 2's voice 1 with its own filter. Nothing waits for the next meow.
echo2step
        lda hpos                ; hpos one on (32 steps round)
        clc
        adc #1
        and #31
        sta hpos
        tay
        lda #0
        sta hist,y              ; this step: no meow yet
        lda esteps
        beq e2none
        tya                     ; esteps ago: its first echo (X = 0)
        sec
        sbc esteps
        and #31
        tay
        ldx #0
        lda hist,y
        bne e2go
        tya                     ; else 2 * esteps ago: the second (X = 1)
        sec
        sbc esteps
        and #31
        tay
        ldx #1
        lda hist,y
        beq e2none
e2go    stx e2i
        ldy #0
        jsr contour             ; (X: the kind)
        ldy #1                  ; slot 1: the echo's
        jsr cstore
        txa                     ; kind * 2 + which echo: its script
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
        ldx #3                  ; SID 2's voice 1
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

; A (semitones) -> A lo, X hi of A * 16 (X in: the high byte, 0 here)
x16     stx stmp
        .rept 4
        asl a
        rol stmp
        .next
        ldx stmp
        rts

; once a frame (seq_tick), mono: the echoes trig_sing planned, one every
; edframes frames on the singer's voice
echoes  lda echo_n
        beq +
        dec echo_t
        bne +
        lda edframes
        sta echo_t
        dec echo_n
        lda echo_k              ; kind * 2 + which echo: its script
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
mrow     .byte 0          ; quant: the smode's qdelta row (smode * 12)
mroot    .byte 0          ; quant: the tonic
bnt      .byte 0          ; bassnote: the note
bnc      .byte 0          ; bassnote: scale steps still to go
harmony  .byte 0          ; SID 2's harmony meow: scale degrees up, 0 = off
mute     .byte 0, 0, 0    ; a cat muted (drums, bass, singer): not played
; the working copy of the open slot: song, tweaks, sname in a row, laid out
; as a slot in slotmem is (slots.asm scopy moves it in one go)
song     .fill SONGLEN
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
sname    .fill SNAMEL     ; the open slot's name (length 0: the style's; slots.asm)
        .cerror tweaks != song + SONGLEN, "song, tweaks, sname: a slot's layout"
hist     .fill 32         ; SID 2's echoes: the singer's last 32 steps
hpos     .byte 0          ; ...this step's
hstep    .byte 0          ; trig_sing: the singer's step byte
ckind    .byte 0          ; contour: the meow kind
e2i      .byte 0          ; echo2step: 0 the first echo, 1 the second
