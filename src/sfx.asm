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
; SID 2's own filter; voice 6 (X = 5) is its voice 3, the bass delay
; (seq.asm bdelay). Their register offset (sidoff) is SID 2's address
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

; once a frame (the bottom IRQ): each voice, nvoice down to 0, its glide,
; pulse width slide, then its script unless it waits; then the after-voices
; work (squelch, dubflt, scduck). Changes A, X, Y.
sfx     ldx nvoice
sfxloop stx sfxv
        lda sidoff,x
        sta rofs                ; rofs = this voice's registers - $d400
        lda gslc,x              ; glide: pitch += gd a frame
        beq glnone
        dec gslc,x
        ldy #0
        lda gd,x
        bpl glpos
        dey                     ; (Y: gd's sign, the high byte)
glpos   clc
        adc ptl,x
        sta ptl,x
        tya
        adc pth,x
        sta pth,x
        jsr p2f
glnone
        lda wslc,x              ; pulse width slide
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
+       lda swait,x             ; waiting: a frame less; the last one runs on
        beq +
        dec swait,x
        bne sfxnext
+       lda sptrh,x
        beq sfxnext             ; idle
        sta sp+1
        lda sptrl,x
        sta sp
        jsr sfxrun
        ldx sfxv
        lda sp
        sta sptrl,x
        lda sp+1
        sta sptrh,x
sfxnext dex
        bmi +
        jmp sfxloop             ; (too far for a branch)
+       jsr squelch             ; then the bass's squelch, the dub filter
        jsr dubflt              ; and the sidechain duck
        jmp scduck

; run commands until a wait or the end; X = voice
; (sp = the command; each handler goes on with sxadv / sfxrun, or returns
; to end the voice's frame)
sfxrun  ldy #0
        lda (sp),y
        cmp #SXCMDS             ; (not a command: the script ends there)
        bcc +
        tya
+       asl a
        tay
        lda sxcmds+1,y          ; the handler's address - 1, pushed: the rts
        pha                     ; below jumps to it
        lda sxcmds,y
        pha
        ldy #1                  ; Y = first argument
        rts

; the SX_* handlers - 1 (for the rts above), indexed by the command
sxcmds  .word sx_end-1, sx_adsr-1, sx_freq-1, sx_ctrl-1, sx_wait-1, sx_pw-1
        .word sx_cut-1, sx_end-1, sx_wslide-1, sx_end-1, sx_end-1
        .word sx_jump-1, sx_end-1, sx_end-1, sx_call-1, sx_poke-1
        ; (7 PSLIDE, 9 CSLIDE, 10 MODF, 12 ROUTE, 13 CHOP: no script used
        ; them, and their per-frame checks cost every voice: gone, they end
        ; a script)
        .word sx_note-1, sx_glide-1, sx_mf-1, sx_mfv-1, sx_stop-1
SXCMDS  = (* - sxcmds) / 2

; SX_CALL lo, hi: run the script there, then the next one here (one level:
; a call inside a call loses the first return)
sx_call clc                     ; return to the next command
        lda sp
        adc #3
        sta retl,x
        lda sp+1
        adc #0
        sta reth,x
        jmp sx_jump

; SX_POKE zp, value: a zero page byte set (sfxy: a spare for the address)
sx_poke lda (sp),y
        sta sfxy
        iny
        lda (sp),y
        ldy sfxy
        sta $00,y
        lda #3
        jmp sxadv

; SX_JUMP lo, hi: go on at that script (sx_call too)
sx_jump lda (sp),y
        pha
        iny
        lda (sp),y
        sta sp+1
        pla
        sta sp
        jmp sfxrun

; SX_END: the gate off (the release runs); then back to the caller of an
; SX_CALL, or idle
sx_end  lda ctl,x
        and #$fe                ; gate bit off
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

; SX_ADSR ad, sr: the envelope, the sustain through the cat's Level
sx_adsr lda (sp),y
        pha
        iny
        lda (sp),y
        jsr srlvl               ; the cat's Level
        cpx #5                  ; the bass delay voice: sustain 5 lower
        bne +
        jsr srlow
+       ldy rofs
        .if HR2                 ; a note's SR (not 0, the gate off): kept
        cmp #0                  ; for sx_ctrl to write right after its
        beq +                   ; gate-on; written before it, it would
        pha                     ; start the ADSR delay bug's count again
        lda ctl,x
        lsr a
        pla
        bcs +                   ; (the gate on: now)
        sta srq,x
        lda #1
        sta srqf,x
        bne ++
        .endif
+       sta $d406,y             ; sustain (high nibble), release
+       pla
        sta $d405,y             ; attack (high nibble), decay
        lda #3
        jmp sxadv

; SX_FREQ lo, hi: the frequency as it is (the drums': through Tune)
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

; SX_CTRL v: the control register $d404 (bit 0 gate, 1 sync, 2 ring mod,
; 3 test, 4 triangle, 5 sawtooth, 6 pulse, 7 noise), the bass's wave by Wave
sx_ctrl lda (sp),y
        cpx #0                 ; the bass (and its delay): the wave
        beq +
        cpx #5
        bne ++
+       jsr bwave
+       sta ctl,x
        ldy rofs
        sta $d404,y
        .if HR2
        cmp #0                  ; a hard restart (CTRL 0): its WAIT is a
        bne +                   ; frame longer (2 frames gated off at ADSR
        lda #1                  ; 0, enough for the envelope to reach 0)
        sta hrx,x
        bne sxc9
+       lsr a                   ; a gate-on: the note's queued SR now
        bcc sxc9
        lda srqf,x
        beq sxc9
        lda #0
        sta srqf,x
        lda srq,x
        sta $d406,y
sxc9
        .endif
        lda #2
        jmp sxadv

; SX_WAIT n: the script waits n frames; the end of this frame's run
sx_wait lda (sp),y
        sta swait,x
        .if HR2
        lda hrx,x               ; (after a hard restart's CTRL 0: a frame
        beq +                   ; more, as W(2): WAIT 1 and 2 both end the
        inc swait,x             ; next frame, WAIT 3 the one after)
        inc swait,x
        lda #0
        sta hrx,x
+
        .endif
        dec swait,x             ; this frame counts as the first
        lda #2
        clc
        adc sp
        sta sp
        bcc +
        inc sp+1
+       rts

; SX_PW lo, hi: the pulse width (12 bits, hi's low nibble), thinner by the
; cat's Level
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

; SX_CUT c: the cutoff (8580 scale)
sx_cut  lda (sp),y
        jsr dark                ; darker for the echoes
        jsr wcut
        lda #2
        jmp sxadv

; SX_WSLIDE dlo, dhi, n: the pulse width + d a frame, for n frames
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

sxadv   clc                   ; skip A bytes, next command
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
        lda cut6581,y           ; (indexed by the 8580 cutoff)
+       sta $d416               ; cutoff bits 3-10 (the low 3 bits stay 0)
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

; the NMI vector's target (catsynth.asm): RESTORE does nothing
nmi_off rti

; all SID registers 0, then volume and filter; sid_detect must have run
sid_init
        ldx #$18                ; $d400-$d418
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
        sta $d40f               ; voice 3 frequency $1000
        lda #$30                ; triangle + sawtooth, no gate
        sta $d412
        ldx #0
        ldy #0                  ; Y = the non-zero reads
-       lda $d41b               ; OSC3: voice 3's waveform output
        beq +
        iny
+       dex
        bne -
        lda #0
        sta sidmodel
        cpy #64
        bcc +
        inc sidmodel
+       lda #$08                ; voice 3 silent again (test bit, then 0)
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
        .if LVROUND             ; (rounded, and at least 1 while the sound
        adc #8                  ; had any: a small cat's quiet echo stays a
        and #$f0                ; whisper, not silence; C clear: s * mul
        bne +                   ; is at most 210)
        lda #$10
        .endif
+       and #$f0
        sta srs
        lda srtmp
        and #$0f
        ora srs
        rts
srl9    lda srtmp
        rts
; each voice's Level byte for getlvl, 1 + its offset from twside (0: none):
; the bass and its delay twside, the meow voices tflags, the drums none
vlvsrc  .byte 1, tflags-twside+1, 0, tflags-twside+1, tflags-twside+1, 1

; voice X: its cat's level 0 (as made) - 8 in A and Y (Z: 0); the bass's
; twside high nibble, the meows' Cat Size (tflags' high nibble, 0 Fat Cat,
; 1 Tomcat, 2 Kitten, 3 Newborn: levels 0, 2, 6, 8); the drums none
getlvl  lda vlvsrc,x
        beq gl9
        tay
        lda twside-1,y
        lsr a                   ; (the high nibble)
        lsr a
        lsr a
        lsr a
        cpy #1
        beq +                   ; twside's: the level itself
        tay
        lda sizelv,y            ; tflags': a Cat Size
+       tay
gl9     rts
sizelv  .byte 0, 2, 6, 8        ; Cat Size 0-3 -> its level
lvmul   .byte 16, 14, 12, 11, 10, 8, 7, 6, 5   ; level 0-8 -> sustain * n/16
lvpw    .byte 16, 15, 14, 13, 12, 11, 10, 9, 8 ; level 0-8 -> pulse distance * n/16

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
srm     .byte 0                 ; srlvl, pwlvl: the factor (sixteenths)
srs     .byte 0                 ; ...the sustain, distance, then the product

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
        lda #$ff                ; (past $ffff: the top)
        sta flo,x
        sta fhi,x
        rts
+       dec dtn
        bne dtup
dt9     rts
dtn     .byte 0                 ; Tune - 8, counted to 0
dtd     .word 0                 ; f / 16

; A = control byte of the bass: its waveform as the Wave setting (0: the
; style's, 1 pulse, 2 saw, 3 triangle), the gate and the rest kept
bwave   pha
        and #$f0                ; (no waveform, the hard restart's $00 or
        beq bw9                 ; a gate-off: left so, the voice is quiet)
        lda btweak
        and #$0f
        beq bw9
        tay
        pla
        and #$0f                ; (the gate, sync, ring, test bits kept)
        ora bwaves,y
        rts
bw9     pla
        rts
bwaves  .byte 0, $40, $20, $10  ; Wave 1-3 -> pulse, sawtooth, triangle bits

; once a frame, after the voices: the bass's squelch (Meowize + Res boost,
; seq.asm trig_bass sets bfenv): each bass note opens SID 1's filter, which
; closes again over about 15 frames, a 303-style "yow" on the resonance;
; only while no meow uses the filter (the singer's voice idle)
BFPEAK  = 170
squelch lda bfenv
        beq sq9
        sec
        sbc #11                 ; (BFPEAK / 11: about 15 frames to 0)
        bcs +
        lda #0
+       sta bfenv
        lda sptrh+1             ; a meow or an echo: it owns the filter
        bne sq9
        lda bfenv
        clc
        adc #14                 ; (closed: 14)
        ldx #1                  ; (as the meow voice: SID 1's filter)
        jmp wcut
sq9     rts
bfenv   .byte 0                 ; the squelch's envelope, BFPEAK down to 0

; once a frame, after the voices: the Dub filter (tflags bit 2; seq.asm
; bdelay sets dfenv): each repeat of the bass delay opens SID 2's filter
; and lets it close over about 32 frames, from bright to a dark "wow" on the
; resonance (at the top while ticked). SID 2's filter belongs to the meow that started last while it
; sings (wcut2): then the repeat is filtered with that meow's vowel.
DFPEAK  = 96
dubflt  lda dfenv
        beq df9
        sec
        sbc #3                  ; (DFPEAK / 3: 32 frames)
        bcs +
        lda #0
+       sta dfenv
        clc
        adc #4                  ; (from about 4 kHz down to the bass's own
        ldx #5                  ; low harmonics, over about 32 frames, the
        jmp wcut                ; resonance's peak moving through them)
df9     rts
dfenv   .byte 0                 ; the Dub filter's envelope, DFPEAK down to 0

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
-       clc                     ; scf = frames left * depth (adds)
        adc scf
        sta scf
        dec scm
        beq +
        lda scdk
        bne -                   ; (always: scdk isn't 0 here)
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
        rts
scout   lda pwl
        sta $d402
        lda pwh
        sta $d403
        rts
scdk    .byte 0                 ; frames of the duck left
scm     .byte 0                 ; depth, then the factor (shifted out)
scf     .byte 0                 ; depth * frames left
scp     .word 0                 ; the bass's pulse width
scr     .word 0                 ; ...times the factor / 256

NV      = 6                     ; voices: SID 1's three, SID 2's three (the
                                ; third: the bass delay)
nvoice  .byte 2                 ; the last voice the player runs (5: SID 2 found)
sid2    .word 0                 ; SID 2's address, 0 = none (sid2.asm)
sidmodel2 .byte 0               ; its model, as sidmodel
cutoff2 .byte 0                 ; its cutoff, as cutoff
cut2own .byte 3                 ; the voice that owns its filter
cdark2  .byte 0                 ; the echo voice's darkening, as cdark
sidoff  .byte 0, 7, 14, $20, $27, $2e   ; SID 2's three: set by sid2_use
vslot   .byte 0, 0, 0, 1, 2, 0  ; the meow contour each voice reads (pitch.asm)
ctour   .fill 3*8               ; contours: the meow, its echo, the harmony
; each voice's state, indexed by X = voice
sptrl   .fill NV              ; the script's next command (high 0: idle)
sptrh   .fill NV
swait   .fill NV              ; frames still to wait (SX_WAIT)
ctl     .fill NV              ; the control register as last written
flo     .fill NV              ; frequency
fhi     .fill NV
pwl     .fill NV              ; pulse width
pwh     .fill NV
wdl     .fill NV              ; pulse width slide: d a frame, frames left
wdh     .fill NV
wslc    .fill NV
        .if HR2
srq     .fill NV              ; a note's SR, for the gate-on (sx_adsr)
srqf    .fill NV              ; ...1: waiting
hrx     .fill NV              ; 1: the next WAIT follows a hard restart
        .endif
retl    .fill NV              ; SX_CALL's return (reth 0: none)
reth    .fill NV
ptl     .fill NV              ; pitch, 1/16 semitones from C0
pth     .fill NV
vnote   .fill NV              ; the note the sequencer gave the voice (semitones)
gd      .fill NV              ; glide: d a frame (signed 1/16 semitones),
gslc    .fill NV              ; frames left
cload   .byte 0               ; the contour in zero page (pitch.asm)
sfxstate_end
        .cerror sfxstate_end - sptrl > 255, "the state is cleared with dex/bne"

