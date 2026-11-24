; ------------------------------------------------------------------ SFX
; A tiny script player, one script per voice, run once per frame from the
; bottom IRQ. Every effect starts with a hard restart (gate off, ADSR 0 for a
; frame) to dodge the SID ADSR bug. Slides run on their own while the script
; waits, so pitch, pulse width and filter can glide together.
;
;   voice 1: kick, bounce, grab, ding (triangle; the ding ring-modulates
;            against voice 3's oscillator for a bell)
;   voice 2: meow (pulse through the resonant lowpass, cutoff swept
;            closed-open-closed: "m-e-ow")
;   voice 3: hiss (noise)
;
; CatSynth: with a second SID (sid2.asm) voices 4 and 5 (X = 3, 4) are its
; voices 1 and 2: the singer's dub echoes and the harmony meow, through
; SID 2's own filter. Their register offset (sidoff) is SID 2's address
; - $d400, so only SIDs at $d420-$d4e0 fit. Mono: nvoice = 2, the loop
; never sees them.

SX_END   = 0              ; gate off, stop
SX_ADSR  = 1              ; ad, sr
SX_FREQ  = 2              ; lo, hi
SX_CTRL  = 3              ; control register
SX_WAIT  = 4              ; frames
SX_PW    = 5              ; lo, hi
SX_CUT   = 6              ; cutoff high byte
SX_PSLIDE = 7             ; dlo, dhi (signed), frames
SX_WSLIDE = 8             ; pulse width slide dlo, dhi, frames
SX_CSLIDE = 9             ; cutoff slide d (signed), frames
SX_MODF  = 10             ; lo, hi: frequency of the ring-mod source voice
SX_JUMP  = 11             ; lo, hi: continue at address (loops)
SX_ROUTE = 12             ; $D417: resonance + filtered voices
SX_CHOP  = 13             ; 1: switch the waveform off every other frame (25 Hz)
SX_CALL  = 14             ; lo, hi: run the script there; its SX_END comes back
SX_POKE  = 15             ; zero page address, value
; CatSynth: pitch in 1/16 semitones from C0 (pitch.asm)
SX_NOTE  = 16             ; d (signed semitones): pitch = (vnote + d) * 16
SX_GLIDE = 17             ; d (signed 1/16 semitones a frame), frames
SX_MF    = 18             ; w, cut: a meow frame (seq.asm's contour), waits a frame
SX_MFV   = 19             ; w, cut, v: the same plus v (signed 1/16 semitones) vibrato
SX_STOP  = 20             ; stop the script, gate untouched (a held note)

HRESTART .macro
        .byte SX_CTRL, $00, SX_ADSR, $00, $00, SX_WAIT, 1
        .endm

; A = FX_xxx; keeps X and Y
sfx_play
        php
        sei
        stx sfxx
        sty sfxy
        tay
        ldx fxvoice,y
        lda fxlo,y
        sta sptrl,x
        lda fxhi,y
        sta sptrh,x
        lda #0
        sta swait,x
        sta pslc,x
        sta wslc,x
        sta cslc,x
        sta chop,x
        sta gslc,x
        ldx sfxx
        ldy sfxy
        plp
        rts

sfx     ldx nvoice
sfxloop stx sfxv
        lda sidoff,x
        sta rofs
        lda gslc,x              ; glide: pitch += gd a frame
        beq glnone
        dec gslc,x
        ldy #0
        lda gd,x
        bpl glpos
        dey
glpos   clc
        adc ptl,x
        sta ptl,x
        tya
        adc pth,x
        sta pth,x
        jsr p2f
glnone
        lda pslc,x              ; pitch slide
        beq +
        dec pslc,x
        ldy rofs
        clc
        lda flo,x
        adc pdl,x
        sta flo,x
        sta $d400,y
        lda fhi,x
        adc pdh,x
        sta fhi,x
        sta $d401,y
+       lda wslc,x              ; pulse width slide
        beq +
        dec wslc,x
        ldy rofs
        clc
        lda pwl,x
        adc wdl,x
        sta pwl,x
        sta $d402,y
        lda pwh,x
        adc wdh,x
        sta pwh,x
        sta $d403,y
+       lda cslc,x              ; filter slide
        beq +
        dec cslc,x
        lda cutoff              ; (this voice's SID)
        cpx #3
        bcc csl1
        lda cutoff2
csl1    clc
        adc cdl,x
        jsr wcut
+       lda chop,x              ; 25 Hz chop: waveform off on odd frames,
        beq +                   ; gate untouched so the envelope runs on
        ldy rofs
        lda frame
        lsr a                   ; C = frame bit 0
        lda ctl,x
        bcc chopon
        and #$0f
chopon  sta $d404,y
+       lda swait,x
        beq +
        dec swait,x
        bne sfxnext
+       lda sptrh,x
        beq sfxnext             ; idle
        .if CHECKPTR
        cmp #$88
        bcc ckp1
ckjam1  .byte $02
ckp1
        .endif
        sta sp+1
        lda sptrl,x
        sta sp
        jsr sfxrun
        ldx sfxv
        lda sp
        sta sptrl,x
        lda sp+1
        .if CHECKPTR
        cmp #$88
        bcc ckp2
ckjam2  .byte $02
ckp2    lda sp+1
        .endif
        sta sptrh,x
sfxnext dex
        bmi +
        jmp sfxloop
+       jsr squelch             ; then the bass's squelch, the dub filter
        jsr dubflt              ; and the sidechain duck
        jmp scduck

; run commands until a wait or the end; X = voice
sfxrun  ldy #0
        lda (sp),y
        asl a
        tay
        lda sxcmds+1,y
        pha
        lda sxcmds,y
        pha
        ldy #1                  ; Y = first argument
        rts

sxcmds  .word sx_end-1, sx_adsr-1, sx_freq-1, sx_ctrl-1, sx_wait-1, sx_pw-1
        .word sx_cut-1, sx_pslide-1, sx_wslide-1, sx_cslide-1, sx_modf-1
        .word sx_jump-1, sx_route-1, sx_chop-1, sx_call-1, sx_poke-1
        .word sx_note-1, sx_glide-1, sx_mf-1, sx_mfv-1, sx_stop-1

sx_call clc                     ; return to the next command
        lda sp
        adc #3
        sta retl,x
        lda sp+1
        adc #0
        sta reth,x
        jmp sx_jump

sx_poke lda (sp),y
        sta sfxy
        iny
        lda (sp),y
        ldy sfxy
        sta $00,y
        lda #3
        jmp sxadv

sx_chop lda (sp),y
        sta chop,x
        lda #2
        jmp sxadv

sx_jump lda (sp),y
        pha
        iny
        lda (sp),y
        sta sp+1
        pla
        sta sp
        jmp sfxrun

sx_route
        lda (sp),y
        jsr wroute
        lda #2
        jmp sxadv

sx_end  lda #0
        sta chop,x
        lda ctl,x
        and #$fe
        ldy rofs
        sta $d404,y
        lda reth,x              ; the end of a called script: go back
        beq +
        sta sp+1
        lda retl,x
        sta sp
        lda #0
        sta reth,x
        jmp sfxrun
+       sta sp+1                ; pointer hi 0 = idle
        rts

sx_adsr lda (sp),y
        pha
        iny
        lda (sp),y
        jsr srlvl               ; the cat's Level
        cpx #5                  ; the bass delay voice: sustain 5 lower
        bne +
        jsr srlow
+       ldy rofs
        sta $d406,y
        pla
        sta $d405,y
        lda #3
        jmp sxadv

sx_freq lda (sp),y
        sta flo,x
        iny
        lda (sp),y
        sta fhi,x
        cpx #2                  ; the drums: the kit's tune
        bne +
        jsr dtune
+       lda fhi,x
        ldy rofs
        sta $d401,y
        lda flo,x
        sta $d400,y
        lda #3
        jmp sxadv

sx_ctrl lda (sp),y
        cpx #0                  ; the bass (and its delay): the wave
        beq +
        cpx #5
        bne ++
+       jsr bwave
+       sta ctl,x
        ldy rofs
        sta $d404,y
        lda #2
        jmp sxadv

sx_wait lda (sp),y
        sta swait,x
        dec swait,x             ; this frame counts as the first
        lda #2
        clc
        adc sp
        sta sp
        bcc +
        inc sp+1
+       rts

sx_pw   lda (sp),y
        sta pwl,x
        iny
        lda (sp),y
        jsr pwlvl               ; the cat's Level: a thinner pulse
        sta pwh,x
        ldy rofs
        sta $d403,y
        lda pwl,x
        sta $d402,y
        lda #3
        jmp sxadv

sx_cut  lda (sp),y
        jsr dark                ; darker for the echoes
        jsr wcut
        lda #2
        jmp sxadv

sx_pslide
        lda (sp),y
        sta pdl,x
        iny
        lda (sp),y
        sta pdh,x
        iny
        lda (sp),y
        sta pslc,x
        lda #4
        jmp sxadv

sx_wslide
        lda (sp),y
        sta wdl,x
        iny
        lda (sp),y
        sta wdh,x
        iny
        lda (sp),y
        sta wslc,x
        lda #4
        jmp sxadv

sx_cslide
        lda (sp),y
        sta cdl,x
        iny
        lda (sp),y
        sta cslc,x
        lda #3
        jmp sxadv

sx_modf ldy modoff,x
        sty sfxy
        ldy #1
        lda (sp),y
        pha
        iny
        lda (sp),y
        ldy sfxy
        sta $d401,y
        pla
        sta $d400,y
        lda #3

sxadv   clc                     ; skip A bytes, next command
        adc sp
        sta sp
        bcc +
        inc sp+1
+       jmp sfxrun

; A = cutoff - the echo darkening of voice X: cdark (the singer's voice,
; mono echoes), cdark2 (SID 2's echo voice); 0 at least
dark    cpx #3
        beq dark2
        sec
        sbc cdark
        bcs +
        lda #0
+       rts
dark2   sec                     ; (cpx set it, but say so)
        sbc cdark2
        bcs +
        lda #0
+       rts

; cutoff A (8580 scale) -> $D416 of voice X's SID, remapped on a 6581;
; uses Y. SID 2's filter is shared by its two voices: the one started
; last owns it while its script runs, the other's writes are dropped.
wcut    cpx #3
        bcs wcut2
        sta cutoff
        ldy sidmodel
        bne +
        tay
        lda cut6581,y
+       sta $d416
        rts
wcut2   cpx cut2own
        beq wc2own
        sta cutoff2             ; (a spare: A back in a moment)
        ldy cut2own
        lda sptrh,y
        bne wc2no               ; the owner still plays
        stx cut2own             ; done: this voice takes over
        lda cutoff2
wc2own  sta cutoff2
        ldy sidmodel2
        bne +
        tay
        lda cut6581,y
+       ldy sidoff+3            ; SID 2 - $d400
        sta $d416,y
wc2no   rts

; $D417 = A, with the resonance toned down on a 6581 (it squeals)
wroute  sta route1               ; (Meowize: wroute1 again with the last)
wroute1 ldy sidmodel
        bne +
        and #$0f
        ora #$70
+       sta wrv
        lda tflags              ; Res boost: the resonance at the top (8580:
        and #2                  ; 15; a 6581, that squeals sooner: 11)
        beq +
        lda wrv
        and #$0f
        ora #$f0
        ldy sidmodel
        bne ++
        and #$bf
        bne ++
+       lda wrv
+       sta wrv
        lda tflags              ; Meowize: voice 1 (the bass) into the filter
        and #1
        ora wrv
        sta $d417
        lda sid2+1              ; SID 2: its echo and harmony voices
        beq wr9                 ; filtered, and with the Dub filter its
        ldy sid2                ; third, the bass delay
        lda #$a3                ; resonance 10, voices 1-2 (as sid2.asm);
        sta wrv                 ; (keeps X: a script's voice)
        lda tflags              ; the Dub filter: voice 3 too, and the
        and #4                  ; resonance at the top (8580 15, 6581 11)
        beq +
        lda #$f7
        sta wrv
+       lda sidmodel2
        bne wr8
        lda wrv                 ; a 6581 squeals sooner: 10 -> 7, 15 -> 11
        cmp #$f0                ; (C: 15)
        lda wrv
        and #$0f
        bcs +
        ora #$70
        bne wr7
+       ora #$b0
wr7     sta wrv
wr8     lda wrv
        sta $d417,y
wr9     rts
wrv     .byte 0
route1  .byte 0
wrbit   .byte 0

nmi_off rti

; all SID registers 0, then volume and filter; sid_detect must have run
sid_init
        ldx #$18
        lda #0
-       sta $d400,x
        dex
        bpl -
        lda #$1f                ; lowpass, full volume
        sta $d418
        lda #$a2                ; resonance 10, filter voice 2 (the meow)
        jsr wroute
        ldx #0                  ; (SID 1's)
        lda #$10
        jmp wcut

; Which SID? Triangle+sawtooth combined reads back strongly on an 8580 and
; almost always 0 on a 6581 (measured on the C64U: 227 vs 1 non-zero reads
; out of 256). sidmodel = 1 if at least 64 reads are non-zero. Run once at
; start, before sid_init (256 reads; it leaves voice 3 silent)
sid_detect
        lda #$08                ; test bit: reset oscillator 3
        sta $d412
        lda #$00
        sta $d40e
        lda #$10
        sta $d40f
        lda #$30                ; triangle + sawtooth, no gate
        sta $d412
        ldx #0
        ldy #0
-       lda $d41b
        beq +
        iny
+       dex
        bne -
        lda #0
        sta sidmodel
        cpy #64
        bcc +
        inc sidmodel
+       lda #$08
        sta $d412
        lda #0
        sta $d412
        rts

; ------------------------------------------------------------------ tweaks
; (the drums' and the bass's, seq.asm twside / twtune / btweak)

; A = SR byte: sustain 5 lower (0 at least), for the bass delay voice
srlow   pha
        and #$0f
        sta srtmp
        pla
        sec
        sbc #$50
        bcs +
        lda #0
+       and #$f0
        ora srtmp
        rts
srtmp   .byte 0

; A = sustain / release of voice X: the sustain times its cat's Level
; (seq.asm: the bass's in twside's high nibble, the meows' in tflags'; 0 as
; made .. 8, about a third). A SID has no volume per voice: the sustain is
; the loudness of a held note. Keeps X.
srlvl   sta srtmp
        jsr getlvl
        beq srl9
        tay
        lda lvmul,y
        sta srm
        lda srtmp
        lsr a
        lsr a
        lsr a
        lsr a
        sta srs
        lda #0                  ; sustain * mul / 16
        ldy srs
        beq +
-       clc
        adc srm
        dey
        bne -
+       and #$f0
        sta srs
        lda srtmp
        and #$0f
        ora srs
        rts
srl9    lda srtmp
        rts
vlvsrc  .byte 1, tflags-twside+1, 0, tflags-twside+1, tflags-twside+1, 1

; voice X: its cat's level 0 (as made) - 8 in A and Y (Z: 0); the bass's
; twside high nibble, the meows' Cat Size (tflags' high nibble, 0 Fat Cat,
; 1 Tomcat, 2 Kitten, 3 Newborn: levels 0, 2, 6, 8); the drums none
getlvl  lda vlvsrc,x
        beq gl9
        tay
        lda twside-1,y
        lsr a
        lsr a
        lsr a
        lsr a
        cpy #1
        beq +
        tay
        lda sizelv,y
+       tay
gl9     rts
sizelv  .byte 0, 2, 6, 8
lvmul   .byte 16, 14, 12, 11, 10, 8, 7, 6, 5
lvpw    .byte 16, 15, 14, 13, 12, 11, 10, 9, 8

; A = the pulse width's high byte for voice X: with its cat's Level the
; pulse thinner (its distance from 0 or 100% x lvpw/16), so the attack's
; peak is quieter too (the sustain can't touch that). Keeps X.
pwlvl   sta srtmp
        jsr getlvl
        beq pwl9
        tay
        lda lvpw,y
        sta srm
        lda srtmp               ; the distance: pwh, or 16 - pwh past 50%
        and #$0f
        cmp #8
        bcc +
        eor #$0f
        adc #0                  ; (C set: 16 - pwh)
+       sta srs
        lda #0                  ; distance * mul / 16
        ldy srs
        beq +
-       clc
        adc srm
        dey
        bne -
+       lsr a
        lsr a
        lsr a
        lsr a
        bne +
        lda #1                  ; (never a silent pulse)
+       ldy srtmp
        cpy #8
        bcc +
        eor #$ff                ; 16 - it
        sec
        adc #16
+       rts
pwl9    lda srtmp
        rts
srm     .byte 0
srs     .byte 0

; flo/fhi,x of the drum voice * the kit's tune: twtune 8 as made, each step
; 1/16 up or down (0: half, 16: one and a half); at most $ffff
dtune   lda twtune
        sec
        sbc #8
        beq dt9
        sta dtn                 ; -8..+8
        lda fhi,x               ; f / 16
        sta dtd+1
        lda flo,x
        .rept 4
        lsr dtd+1
        ror a
        .next
        sta dtd
        lda dtn
        bpl dtup
-       lda flo,x               ; down: f -= f/16, -dtn times
        sec
        sbc dtd
        sta flo,x
        lda fhi,x
        sbc dtd+1
        sta fhi,x
        inc dtn
        bne -
        rts
dtup    lda flo,x               ; up: f += f/16, dtn times
        clc
        adc dtd
        sta flo,x
        lda fhi,x
        adc dtd+1
        sta fhi,x
        bcc +
        lda #$ff
        sta flo,x
        sta fhi,x
        rts
+       dec dtn
        bne dtup
dt9     rts
dtn     .byte 0
dtd     .word 0

; A = control byte of the bass: its waveform as the Wave setting (0: the
; style's, 1 pulse, 2 saw, 3 triangle), the gate and the rest kept
bwave   pha
        lda btweak
        and #$0f
        beq bw9
        tay
        pla
        and #$0f
        ora bwaves,y
        rts
bw9     pla
        rts
bwaves  .byte 0, $40, $20, $10

; once a frame, after the voices: the bass's squelch (Meowize + Res boost,
; seq.asm trig_bass sets bfenv): each bass note opens SID 1's filter, which
; closes again over about 15 frames, a 303-style "yow" on the resonance;
; only while no meow uses the filter (the singer's voice idle)
BFPEAK  = 170
squelch lda bfenv
        beq sq9
        sec
        sbc #11
        bcs +
        lda #0
+       sta bfenv
        lda sptrh+1             ; a meow or an echo: it owns the filter
        bne sq9
        lda bfenv
        clc
        adc #14                 ; (closed: 14)
        ldx #1
        jmp wcut
sq9     rts
bfenv   .byte 0

; once a frame, after the voices: the Dub filter (tflags bit 2; seq.asm
; bdelay sets dfenv): each repeat of the bass delay opens SID 2's filter
; and lets it close over about 32 frames, from bright to a dark "wow" on the
; resonance (at the top while ticked). SID 2's filter belongs to the meow that started last while it
; sings (wcut2): then the repeat is filtered with that meow's vowel.
DFPEAK  = 96
dubflt  lda dfenv
        beq df9
        sec
        sbc #3
        bcs +
        lda #0
+       sta dfenv
        clc
        adc #4                  ; (from about 4 kHz down to the bass's own
        ldx #5                  ; low harmonics, over about 32 frames, the
        jmp wcut                ; resonance's peak moving through them)
df9     rts
dfenv   .byte 0

; once a frame, after the voices: the sidechain. A kick (trig_drum) sets
; scdk = SCLEN; the bass's pulse width is then pw * (256 - 3 * depth *
; frames left) / 256 (depth: twside, 0-8), back to pw at the
; end: quieter and thinner, swelling back over SCLEN frames
SCLEN   = 12
scduck  lda scdk
        bne +
        rts
+       dec scdk
        lda twside              ; depth 0 (off) - 8
        and #$0f
        bne +
        rts
+
        sta scm                 ; depth * frames left * 3, at most 255
        lda scdk
        beq scout               ; the last frame: the bass's own pw again
        ldy #0
        sty scf
-       clc
        adc scf
        sta scf
        dec scm
        beq +
        lda scdk
        bne -
+       lda scf                 ; (<= 8 * 11 = 88)
        cmp #85
        bcc +
        lda #255
        bne ++
+       sta scm
        asl a
        adc scm                 ; * 3
+        eor #$ff                ; 255 - it: the factor
        sta scm
        lda pwl                 ; pw * factor / 256
        sta scp
        lda pwh
        sta scp+1
        lda #0
        sta scr
        sta scr+1
        ldy #8
-       lsr scm
        bcc +
        clc
        lda scr
        adc scp
        sta scr
        lda scr+1
        adc scp+1
        sta scr+1
+       lsr scr+1
        ror scr
        dey
        bne -
        lda scr                 ; (the product's high part: pw * f >> 8)
        sta $d402
        lda scr+1
        sta $d403
sc9     rts
scout   lda pwl
        sta $d402
        lda pwh
        sta $d403
        rts
scdk    .byte 0
scm     .byte 0
scf     .byte 0
scp     .word 0
scr     .word 0

NV      = 6                     ; voices: SID 1's three, SID 2's three (the
                                ; third: the bass delay)
nvoice  .byte 2                 ; the last voice the player runs (4: SID 2 found)
sid2    .word 0                 ; SID 2's address, 0 = none (sid2.asm)
sidmodel2 .byte 0               ; its model, as sidmodel
cutoff2 .byte 0                 ; its cutoff, as cutoff
cut2own .byte 3                 ; the voice that owns its filter
cdark2  .byte 0                 ; the echo voice's darkening, as cdark
sidoff  .byte 0, 7, 14, $20, $27, $2e   ; SID 2's three: set by sid2_use
modoff  .byte 14, 0, 7, $2e, $20, $27   ; ring-mod source of each voice
vslot   .byte 0, 0, 0, 1, 2, 0  ; the meow contour each voice reads (pitch.asm)
ctour   .fill 3*8               ; contours: the meow, its echo, the harmony
sptrl   .fill NV
sptrh   .fill NV
swait   .fill NV
ctl     .fill NV
flo     .fill NV
fhi     .fill NV
pwl     .fill NV
pwh     .fill NV
pdl     .fill NV
pdh     .fill NV
pslc    .fill NV
wdl     .fill NV
wdh     .fill NV
wslc    .fill NV
cdl     .fill NV
cslc    .fill NV
chop    .fill NV
retl    .fill NV
reth    .fill NV
ptl     .fill NV              ; pitch, 1/16 semitones from C0
pth     .fill NV
vnote   .fill NV              ; the note the sequencer gave the voice (semitones)
gd      .fill NV
gslc    .fill NV
cload   .byte 0               ; the contour in zero page (pitch.asm)
sfxstate_end
        .cerror sfxstate_end - sptrl > 255, "the state is cleared with dex/bne"

