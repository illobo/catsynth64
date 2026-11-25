; ------------------------------------------------------------------ CatSynth 64
; Three cats with fixed jobs: the drum cat (SID voice 3), the bass cat
; (voice 1) and the singer cat (voice 2, the filtered meow with its dub
; echoes). Polled once a frame at the bottom of the screen, interrupts
; off: keys, sequencer, sound, cats, grids.
;
; Keys
;   1-9, 0      song slot (SHIFT: a style)   SPACE   play / stop
;   + -         tempo                        CRSR    move the cursor
;   RETURN      the cell's left job          SHIFT+RETURN  its right job
;   Q A         value up / down              K       length / meow kind
;   G           slide (bass)                 C=      the next cat's tab
;   F1 F3 F5 F7 edit bar A B C D             C       next song chain
;   E           echo delay (dub)             X       copy bar A here
;   DEL         clear the cursor's row       S / L   the disk page (diskui.asm)
;   T           the open cat's settings      CTRL+1-3  mute
;   , .         singer transpose (SHIFT: bass)   M  the mode   H  harmony
;   <-          live play (the looper)       RUN/STOP  help
; Mouse (port 1) and joystick (port 2, as a mouse: ui.asm, joy_edit): the
; pointer; left / right click.
;
; Memory: program from $0801 (BASIC stub), screen/charset/sprites at
; $c000-$cfff (screen.asm). Zero page: $02, $21-$22, $66-$9b sound and
; sequencer, $a0-$db here, $f0-$f6 screen, $fb-$fe the disk page
; (diskui.asm).

.weak
WEB      = 0              ; the web edition (make web): the ten techno songs
                          ; built in, in the slots at start (slots.asm)
; sound choices, each 1 = on (build with -D NAME=0 for the other, to compare
; by ear; ab/CHANGES.md):
LVROUND  = 0              ; Level / Cat Size scale the sustain rounded, never
                          ; to 0 (sfx.asm srlvl)
MEOWFIT  = 0              ; a meow the next one cuts short sings a flatter
                          ; Bend, so it ends near its note (seq.asm bcap)
HR2      = 1              ; the hard restart 2 frames, the note's SR written
                          ; after its gate-on (the ADSR delay bug; sfx.asm)
LEGATO   = 1              ; a bass slide over a note still sounding glides
                          ; from its pitch, no restart (seq.asm legato)
ECHOBAR  = 0              ; one SID, a lone meow in its bar: only the echoes
                          ; that end before it comes round again (0: both)
.endweak
frame    = $02
cdark    = $21
sp       = $66
rofs     = $68
sfxv     = $69
sfxx     = $6a
sfxy     = $6b
cutoff   = $6c
sidmodel = $6e

pmode    = $a0            ; live play (the looper): keyboard rows are pads
running  = $a1            ; 0: stopped
joy      = $a2            ; joystick 2 held (1 = pressed: bits 0-4 up down left right fire)
joyl     = $a3            ; ...last frame
joyn     = $a4            ; ...pressed this frame
catt     = $a6            ; 3 bytes: frames the pose holds
lstep    = $a9
gp       = $aa            ; 2 bytes
cp       = $ac            ; 2 bytes
curx     = $ae            ; cursor: step 0-15
cury     = $af            ; cursor: cat 0-2
kbd      = $b0            ; 8 bytes: keys held, a byte per matrix column (1 = held)
kprev    = $b8            ; 8 bytes: last frame's
knew     = $c0            ; 8 bytes: pressed this frame
eslot    = $c8            ; the pattern slot being edited (0-3)
ep       = $c9            ; 2 bytes: its address
fused    = $cb            ; fire held and used for editing: no tap
lastv    = $cc            ; 3 bytes: the value a step gets when switched on
msgt     = $d0            ; frames the message stays
dirty    = $d1            ; info and song line to redraw
chainp   = $d2            ; the chain preset shown last
tmp      = $d3
tmp2     = $d4
audt     = $d5            ; frames until an auditioned bass note is let go
lbar     = $d6            ; the bar drawn last
rec      = $d8            ; looper recording
padv     = $d9            ; the pad's step byte
padc     = $da            ; its cat
helpon   = $db            ; the help overlay is up


; keys: column * 8 + row of the C64 matrix (column: the $dc00 line pulled
; low, kbd's index; row: the $dc01 bit read)
K_DEL    = 0*8+0
K_RETURN = 0*8+1
K_CRSRLR = 0*8+2
K_F7     = 0*8+3
K_F1     = 0*8+4
K_F3     = 0*8+5
K_F5     = 0*8+6
K_CRSRUD = 0*8+7
K_A      = 1*8+2
K_S      = 1*8+5
K_E      = 1*8+6
K_LSHIFT = 1*8+7
K_C      = 2*8+4
K_X      = 2*8+7
K_G      = 3*8+2
K_K      = 4*8+5
K_H      = 3*8+5
K_COMMA  = 5*8+7
K_M      = 4*8+4
K_PERIOD = 5*8+4
K_PLUS   = 5*8+0
K_L      = 5*8+2
K_MINUS  = 5*8+3
K_RSHIFT = 6*8+4
K_CBM    = 7*8+5
K_CTRL   = 7*8+2
K_T      = 2*8+6
K_P      = 5*8+1
K_SPACE  = 7*8+4
K_Q      = 7*8+6
K_STOP   = 7*8+7
K_ARROW  = 7*8+1          ; <- : live play mode
K_W      = 1*8+1

; A = pressed this frame? (Z clear when yes)
pressed .macro key
        lda knew + (\key >> 3)
        and #1 << (\key & 7)
        .endm
; A = held now? (Z clear when yes)
held    .macro key
        lda kbd + (\key >> 3)
        and #1 << (\key & 7)
        .endm

STAGE_LEN  = $f00               ; the stage's bitmap: rows 0-11, 3840 bytes

        * = $0801               ; the BASIC stub: 2026 SYS start
        .word +, 2026
        .null $9e, format("%d", start)
+       .word 0

start   sei
        lda #$36                ; no BASIC ROM: RAM up to $bfff (the KERNAL stays
        sta $01                 ; for the disk and the IRQ entry)
        ldx #0                  ; the stage's bitmap: loaded at the end of the
-       .for o = 0, o < STAGE_LEN, o += $100   ; program file, to $e000 under
        lda stage_data+o,x      ; the KERNAL (writes go to the RAM), before
        sta SCR_BITMAP+o,x      ; anything uses its room (the disk page's
        .next                   ; buffers, the screen at $c000)
        inx
        bne -
        lda #<nmi_off           ; RESTORE (and RUN/STOP+RESTORE: RUN/STOP is the
        sta $0318               ; help key) does nothing
        lda #>nmi_off
        sta $0319
        lda #$7f                ; no CIA interrupts: we poll
        sta $dc0d
        sta $dd0d
        lda $dc0d
        lda $dd0d
        cld
        ldx #$ff
        txs
        lda #0
        ldx #$a0                ; our zero page ($a0-$db)
-       sta $00,x
        inx
        cpx #$dc
        bne -
        sta cdark
        sta frame
        ldx #sfxstate_end-sptrl
-       sta sptrl-1,x           ; (more than 128 bytes: dex/bne)
        dex
        bne -
        lda #1                  ; a step switched on: drum role 1,
        sta lastv
        lda #13                 ; bass note 13 (the root),
        sta lastv+1
        lda #$26                ; degree 5, a meow
        sta lastv+2
        jsr pal_detect
        lda ntsc                ; NTSC: the pitch tables for its clock (the
        beq +                   ; PAL ones play 0.65 semitone sharp there)
        ldx #0
-       .for i = 0, i < 380, i += 190
        lda ftntsc + i,x
        sta ftl + i,x
        .next
        inx
        cpx #190
        bne -
+       jsr sid_detect
        jsr sid_init
        jsr sid2_init           ; [sid2] a second SID? (sid2.asm)
        lda #0
        jsr newstyle            ; the demo song: dancehall
        lda #1
        sta running
        jsr title_run           ; the title, the band playing (title_tick)
        jsr sfx_stop            ; the main screen: the ten song slots, the
        lda cstyle              ; style that was playing open (slots.asm;
        jsr slots_init          ; the web edition: slot 1)
        jsr screen_init         ; then the main screen
        jsr ui_init             ; its panel in the UI font (ui.asm); IRQs on
        lda #$ff
        sta lstep
        ldx #<msg_start         ; (the first 3 seconds: where the help is)
        ldy #>msg_start
        jsr message

; ------------------------------------------------------------------ main loop
loop    lda #$fa                ; once a frame, in the lower border (line 250)
-       cmp $d012
        bne -
        jsr music
        jsr slots_tick          ; a slot / style switch on the bar line
        jsr pulse_frame         ; the border's beat pulse (ui.asm)
        jsr poses
        jsr screen_frame
        jsr input               ; (the keys' own work first: infos then
        jsr audition_tick       ; sees what time is left, roomy)
        jsr infos
        inc frame
-       lda $d012               ; (off line 250 first: not twice a frame)
        cmp #$fa
        beq -
        jmp loop

; the title's frame: the band plays (title_run draws the screen itself)
title_tick
        jsr music
        ldx #7                  ; 1-0: that style now (the keyboard read as
-       lda colmask,x           ; input does, the new presses into knew)
        sta $dc00
        lda $dc01
        eor #$ff
        tay
        eor kprev,x
        sta knew,x
        tya
        and knew,x
        sta knew,x
        tya
        sta kprev,x
        dex
        bpl -
        lda #$ff
        sta $dc00
        jsr digit
        bcs +
        cpx #NSTYLES
        bcc attstyle
+       lda bar                 ; attract mode: when the song's chain comes
        cmp attbar              ; round (bar 0 again) after 8 bars at least,
        beq att9                ; the next style
        sta attbar
        jsr stage_cycle         ; (and the lights change colour each bar)
        inc attn
        lda bar
        bne att9
        lda attn
        cmp #9                  ; (8 played: this is the 9th bar seen)
        bcc att9
        ldx cstyle              ; the next style, round
        inx
        cpx #NSTYLES
        bcc attstyle
        ldx #0
attstyle  txa
        pha
        jsr sfx_stop            ; (changes X)
        pla
        tax
        jsr seq_load            ; (not newstyle: the title owns the screen)
        lda #1
        sta title_busy          ; (~6000 cycles: the title's extras wait)
        lda #0
        sta attn
        lda #$ff
        sta attbar
att9    jmp poses
attbar    .byte $ff             ; the bar seen last
attn      .byte 0               ; bars seen with this style

; the sequencer and the sound, once a PAL frame: on NTSC (60 Hz) every
; sixth frame is skipped, so songs and meows keep their PAL speed
music   lda ntsc
        beq +
        dec ntick
        bpl +
        lda #5                  ; (the sixth: no tick)
        sta ntick
        rts
+       lda running
        beq +
        jsr seq_tick
        jsr follow
+       jmp sfx

; ntsc = 0 on PAL (312 lines), 1 on NTSC (262/263): from the line count
pal_detect
-       lda $d011
        bpl -                   ; a line from 256 on
-       lda $d012
        cmp #$10
        bcs +                   ; line 272 or more: PAL
        bit $d011
        bmi -
        lda #1
        sta ntsc
        rts
+       lda #0
        sta ntsc
        rts
ntsc    .byte 0
ntick   .byte 5                 ; NTSC frames to the one skipped

; ------------------------------------------------------------------ input
; the keyboard matrix into kbd (1 = held) and knew (pressed now); joystick
; 2 into joy / joyn. A joystick that is held pulls the keyboard's column
; lines too, so the keyboard is not scanned then.
input   jsr input1
        lda #$7f                ; port 1's POTs (the mouse) for next frame
                                ; ($dc00 bits 7/6 = 0/1: SID reads port 1)
        sta $dc00
        rts
input1  jsr mouse_fake          ; (c64bridge's stand-in for a mouse)
        jsr mouse_read          ; C: a mouse button held (ui.asm)
        php
        lda #$ff                ; no column pulled: $dc00 reads port 2 alone
        sta $dc00
        lda $dc00
        eor #$ff                ; (low active: 1 = pressed)
        and #$1f
        sta joy
        eor joyl                ; new: down now, not last frame
        and joy
        sta joyn
        lda joy
        sta joyl
        ldx #7
        plp
        bcs +
        lda joy
        beq kscan
+       lda #0                  ; joystick or mouse busy: no keys this frame
-       sta kbd,x
        sta knew,x
        dex
        bpl -
        jmp dispatch
kscan   lda colmask,x           ; column X pulled low: its rows on $dc01
        sta $dc00
        lda $dc01
        eor #$ff
        sta kbd,x
        dex
        bpl kscan
        lda #$ff
        sta $dc00
        lda $dc01               ; a mouse button (port 1: the keyboard's row
        cmp #$ff                ; lines) that went down during the scan
        beq +                   ; pulled a whole row: the scan is no good
        ldx #7
        lda #0
-       sta kbd,x
        sta knew,x
        dex
        bpl -
        jmp dispatch
+       lda #0
        sta kany
        ldx #7
-       lda kbd,x               ; pressed now: held and not last frame
        eor kprev,x
        and kbd,x
        sta knew,x
        ora kany
        sta kany
        lda kbd,x
        sta kprev,x
        dex
        bpl -
        jsr krepeat             ; (a cursor / value key held: repeats)
        lda kany                ; no key went down (most frames): only the
        bne dispatch            ; joystick, unless the help or the disk
        lda helpon              ; page is up (they take the joystick too)
        ora diskon
        bne dispatch
        jmp joy_edit

dispatch
        lda helpon              ; help up: any key or fire closes it
        beq +
        jmp helpkeys
+       lda diskon              ; the disk page: all keys to it (diskui.asm);
        beq +                   ; the joystick is the pointer everywhere
        jsr joy_edit
        jmp dkeys
+       #pressed K_STOP         ; RUN/STOP: the help overlay (in live play
        beq +                   ; only held alone: kalone)
        lda pmode
        beq kdhelp
        jsr kalone
        bne +
kdhelp  jmp help_open
+       jsr keys_mute
        lda pmode
        beq +
        jsr keys_live
        jmp joy_edit
+       jsr keys_play
        lda tweakon             ; a cat's settings page (ui.asm)
        beq +
        jsr joy_edit
        jmp keys_tweak
+       jsr keys_edit
        jmp joy_edit

; Z set when at most one key is held (the SHIFTs not counted): a key that
; came with two others may be a ghost of them (no diodes in the matrix)
kalone  ldx #7
        ldy #0                  ; (Y: keys held)
-       lda kbd,x
        cpx #1
        bne +
        and #$7f                ; (left SHIFT)
+       cpx #6
        bne +
        and #$ef                ; (right SHIFT)
+       beq ++
-       asl a                   ; count its bits
        bcc +
        iny
+       bne -                   ; (A 0: none left)
+       dex
        bpl --
        cpy #2
        bcc +
        lda #1                  ; (Z clear: more than one)
        rts
+       lda #0
        rts
; key repeat: the last repeatable key pressed (CRSR, Q / A, + -, , .), held
; KRDELAY frames, comes again every KRRATE frames (into knew, kany)
KRDELAY  = 20
KRRATE   = 4
krepeat lda pmode               ; (not in live play: Q and A are pads)
        bne kroff
        lda kany
        beq kr2
        ldx #len(KRCOL)-1       ; a new press: one of the repeatable keys?
-       ldy krcol,x
        lda knew,y
        and krbit,x
        bne +
        dex
        bpl -
        lda #$ff                ; (no: nothing repeats)
        sta krk
        rts
+       stx krk
        lda #0
        sta krn
        rts
kr2     ldx krk                 ; none new: the one held still?
        bmi kr9
        ldy krcol,x
        lda kbd,y
        and krbit,x
        beq kroff
        inc krn
        lda krn
        cmp #KRDELAY
        bcc kr9
        sbc #KRRATE             ; (every KRRATE frames after the delay)
        sta krn
        lda krbit,x
        sta knew,y
        sta kany
kr9     rts
kroff   lda #$ff
        sta krk
        rts
KRCOL   = [K_CRSRLR >> 3, K_CRSRUD >> 3, K_Q >> 3, K_A >> 3, K_PLUS >> 3, K_MINUS >> 3, K_COMMA >> 3, K_PERIOD >> 3]
krcol   .byte KRCOL
krbit   .byte 1 << (K_CRSRLR & 7), 1 << (K_CRSRUD & 7), 1 << (K_Q & 7), 1 << (K_A & 7)
        .byte 1 << (K_PLUS & 7), 1 << (K_MINUS & 7), 1 << (K_COMMA & 7), 1 << (K_PERIOD & 7)
krk     .byte $ff               ; the key repeating (index), $ff none
krn     .byte 0                 ; frames it is held
kany    .byte 0                 ; input: any knew bit this frame
kwold   .byte 0                 ; W: the swing before

; $dc00 for keyboard column 0-7: that line low
colmask .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f

; the digit keys 1-9, 0 as (column, row bit); X = digit index 0-9
digcol  .byte 7, 7, 1, 1, 2, 2, 3, 3, 4, 4
digrow  .byte 1, 8, 1, 8, 1, 8, 1, 8, 1, 8

; X = a digit pressed now (0 = key "1" ... 9 = key "0"), C clear; C set: none
digit   ldx #0
-       ldy digcol,x
        lda knew,y
        and digrow,x
        bne +
        inx
        cpx #10
        bne -
        sec
        rts
+       clc
        rts

; CTRL + 1 / 2 / 3: the drums, bass, singer muted / back (ui.asm mutetog)
keys_mute
        #held K_CTRL
        beq +
        jsr digit
        bcs +
        cpx #3
        bcs +
        jmp mutetog
+       rts

; Z clear: a SHIFT key held
shifted #held K_LSHIFT
        bne +
        #held K_RSHIFT
+       rts

; the keys that work while editing and on a settings page: slots, styles,
; play / stop, tempo, echo, chain, transposes, mode, harmony, live play,
; the disk page
keys_play
        jsr kslots
        jmp kpspace

; 1-0 (the slots), SHIFT+1-0 (new sounds): keys_play's, and live play's
kslots  #held K_CTRL            ; (CTRL + 1-3: a mute, keys_mute)
        bne kp9
        jsr digit               ; 1-0: a song slot; SHIFT: a style's sounds;
        bcs +                   ; the style list up: a style (slots.asm)
        cpx #NSLOTS             ; (the ten digits: all slots)
        bcs +
        stx kpdig
        lda spick
        bne kpstyle
        jsr shifted
        bne kpstyle
        lda kpdig
        jmp slot_select
kpstyle lda spick
        beq kpst2
        jsr tweak_close
kpst2   lda kpdig
        jmp style_select
+
kp9     rts

; SPACE play / stop (SHIFT+SPACE: pause / go on, as the play button)
kspace  #pressed K_SPACE
        beq kp9
        jsr shifted
        beq +
        jmp b_play
+       jmp startstop

; + - the tempo (frames a step, 4-15: + is fewer)
ktempo  #pressed K_PLUS
        beq +
        lda tempo
        cmp #5
        bcc +
        dec tempo
        jsr retempo
+       #pressed K_MINUS
        beq +
        lda tempo
        cmp #15
        bcs +
        inc tempo
        jsr retempo
+       rts

kpspace jsr kspace
        jsr ktempo
        #pressed K_W            ; W: the swing up (to its cap, then 0);
        beq kpw9                ; SHIFT+W down
        jsr shifted
        bne +
        lda swing
        sta kwold
        clc
        adc #1
        jsr setswing
        lda swing               ; (at the cap it stays: round to 0)
        cmp kwold
        bne kpw9
        lda #0
        jsr setswing
        jmp kpw9
+       lda swing
        beq kpw9
        sec
        sbc #1
        jsr setswing
kpw9    #pressed K_E            ; echo: off, 2, 3, 4, 6, 8 steps
        beq kp2
        ldx #0                  ; find the setting now; take the next
-       lda echos,x
        cmp esteps
        beq +
        inx
        cpx #len(ECHOS)
        bne -
        ldx #$ff                ; not in the list: start with the first
+       inx
        cpx #len(ECHOS)
        bcc +
        ldx #0
+       lda echos,x
        sta esteps
        jsr store3              ; (keeping the singer's transpose)
        jsr seq_retempo
        lda #$80
        sta dirty
kp2     #pressed K_C            ; the next song chain
        beq +
        jsr nextchain
+       #pressed K_COMMA        ; , . the singer's transpose; < > the bass's
        beq ++
        jsr shifted
        bne +
        lda #$ff                ; (after shifted: it leaves A 0)
        jsr transpose
        jmp ++
+       lda #$ff
        jsr btranspose
+       #pressed K_PERIOD
        beq ++
        jsr shifted
        bne +
        lda #1
        jsr transpose
        jmp ++
+       lda #1
        jsr btranspose
+       #pressed K_M            ; the mode
        beq +
        jsr nextmode
+       #pressed K_H            ; the harmony meow (second SID)
        beq +
        jsr harmkey
+       #pressed K_ARROW        ; live play (a settings page closes first)
        beq +
        lda tweakon
        beq kplive
        jsr tweak_close
kplive  lda #1
        sta pmode
        jmp status
+       #pressed K_S            ; the disk page
        bne +
        #pressed K_L
        beq ++
+       jmp disk_open
+       rts
ECHOS    = [0, 2, 3, 4, 6, 8]
echos   .byte ECHOS             ; E's echo delays, in steps

; tempo changed: into the song (song+1), the swing kept under it
retempo lda swing               ; the swing stays under the tempo (setswing
        jsr setswing            ; caps it at tempo - 3)
        lda tempo
        sta song+1
        jsr seq_retempo
        lda #$80
        sta dirty
        rts

; the editing keys (the grids up, no settings page): cursor, cells, values,
; bars, clear, copy
keys_edit
        #pressed K_CRSRLR
        beq ++
        jsr shifted
        beq +
        jsr curleft
        jmp ++
+       jsr curright
+       #pressed K_CRSRUD
        beq ++
        jsr shifted
        beq +
        jsr curup
        jmp ++
+       jsr curdown
+       #pressed K_RETURN       ; the cell's left / right job (ui.asm act)
        beq ++
        jsr shifted
        beq +                   ; (not shifted: A = 0, the left job)
        lda #1
+       jsr act
+       #pressed K_T            ; the meows' tweaks page
        beq +
        jsr tweak_open
+       #pressed K_CBM          ; the next cat's tab
        beq +
        jsr nexttab
+       #pressed K_Q
        beq +
        lda #1
        jsr value
+       #pressed K_A
        beq +
        lda #$ff
        jsr value
+       #pressed K_K
        beq +
        lda #1
        jsr modify
+       #pressed K_G
        beq +
        jsr slide
+       #pressed K_F1
        beq +
        lda #0
        jsr editslot
+       #pressed K_F3
        beq +
        lda #1
        jsr editslot
+       #pressed K_F5
        beq +
        lda #2
        jsr editslot
+       #pressed K_F7
        beq +
        lda #3
        jsr editslot
+       #pressed K_DEL
        beq +
        jsr clearrow
+       #pressed K_X
        beq +
        jsr copya
+       rts

; joystick: directions move (auto-repeat); fire held + a direction edits,
; and then letting fire go is no tap
; joystick 2 works as a mouse: it moves the pointer (1 pixel a frame, 2
; after 8 frames, 4 after 20), fire is a left click when let go, fire held
; for half a second a right click (ui.asm ui_click)
joy_edit
        lda joy
        and #$0f
        bne +
        sta jheld               ; still
        jmp jfire
+       sta jdir
        lda jheld
        cmp #40
        bcs +
        inc jheld
+       ldx #1                  ; the speed
        lda jheld
        cmp #8
        bcc +
        ldx #2
        cmp #20
        bcc +
        ldx #4
+       stx jsp
        jsr jcell               ; over the matrix: a cell a push (C set: done)
        bcs jmoved
        lsr jdir                ; up
        bcc +
        lda my
        sec
        sbc jsp
        sta my
+       lsr jdir                ; down
        bcc +
        lda my
        clc
        adc jsp
        sta my
+       lsr jdir                ; left
        bcc +
        lda mx
        sec
        sbc jsp
        sta mx
        bcs +
        dec mx+1
+       lsr jdir                ; right
        bcc +
        lda mx
        clc
        adc jsp
        sta mx
        bcc +
        inc mx+1
+
jmoved  jsr mclamp
        lda #1
        sta mseen
        jsr mhover
jfire   lda joy
        and #$10                ; fire
        beq jup
        lda jfhold              ; held: half a second is a right click
        cmp #255
        bcs +
        inc jfhold
+       lda jfhold
        cmp #25                 ; 25 PAL frames
        bne +
        lda #1
        sta jfr
        sta mseen
        jmp ui_click            ; (A = 1: right)
+       rts
jup     lda jfhold              ; let go: a left click (not after a right
        beq +                   ; one, nor when the press closed the help)
        lda jfr
        ora fused
        bne jclr
        lda #1
        sta mseen
        lda #0
        jsr ui_click
jclr    lda #0
        sta jfhold
        sta jfr
        sta fused
+       rts
; the joystick over the matrix (no page over it): the pointer jumps a cell
; a push, to the cell's middle (a step is 16 pixels, a row 8), and on held,
; after 16 frames, a cell every 4: pixel steps were slow for 16 x 8 cells.
; C set when it did (or waits for the next repeat); clear: move as usual
jc0     clc
        rts
jc9     sec
        rts
jcell   lda tweakon
        ora diskon
        ora helpon
        bne jc0
        lda my                  ; rows 15-21: y 120-175
        cmp #MROW*8
        bcc jc0
        cmp #(MROW+NROWS)*8
        bcs jc0
        lda mx+1                ; columns 7-38: x 56-311
        bne +
        lda mx
        cmp #MCOL*8
        bcc jc0
+       lda jheld               ; (1: the push's first frame)
        cmp #1
        beq jc2
        cmp #16
        bcc jc9
        lda frame
        and #3
        bne jc9
jc2     lsr jdir                ; up
        bcc +
        lda my
        sbc #8                  ; (C set)
        sta my
+       lsr jdir                ; down
        bcc +
        lda my
        adc #8-1                ; (C set: + 8)
        sta my
+       lsr jdir                ; left
        bcc +
        lda mx
        sbc #16
        sta mx
        bcs +
        dec mx+1
+       lsr jdir                ; right
        bcc +
        lda mx
        adc #16-1
        sta mx
        bcc +
        inc mx+1
+       lda my                  ; to the middle of the cell
        and #$f8
        ora #4
        sta my
        lda mx                  ; x: 56 + 16 * step + 8
        sec
        sbc #MCOL*8
        tax
        lda mx+1
        sbc #0
        sta mx+1
        txa
        and #$f0
        clc
        adc #MCOL*8+8
        sta mx
        bcc +
        inc mx+1
+       sec
        rts
jheld   .byte 0                 ; frames a direction is held (to 40)
jdir    .byte 0                 ; the directions, shifted out
jsp     .byte 0                 ; pixels a frame
jfhold  .byte 0                 ; frames fire is held (to 255)
jfr     .byte 0                 ; that press made a right click

; SPACE: play (from the top) / stop
startstop
        lda running
        eor #1
        sta running
        bne +
        jsr sfx_stop
        rts
+       jmp seq_apply           ; from the top

; silence: all gates off, scripts idle, no echoes
sfx_stop
        ldx nvoice              ; [sid2] 2, or 4: SID 2's voices too
-       lda #0
        sta sptrh,x
        lda ctl,x
        and #$fe
        sta ctl,x
        ldy sidoff,x            ; the voice's control register, gate off
        sta $d404,y
        dex
        bpl -
        lda #0
        sta echo_n
        sta cdark               ; (a mono echo cut short: no darkness left)
        rts

; A = style: its preset song into the open slot (the tests; the slots
; start this way)
newstyle
        pha
        jsr sfx_stop
        pla
        tax
        jsr seq_load
        lda #0
        sta sname
        jmp songshow
kpdig   .byte 0

; ------------------------------------------------------------------ editing
; CRSR: the cursor a step left / right (round), a row up / down
curleft dec curx
        bpl +
        lda #15
        sta curx
+       jmp cmoved
curright
        inc curx
        lda curx
        and #15
        sta curx
        jmp cmoved
curup   lda crow                ; the matrix's rows; past the top or the
        bne +                   ; bottom the window scrolls (ui.asm)
        lda #1
        jmp scroll
+       dec crow
        jmp cmoved
curdown lda crow
        cmp #NROWS-1
        bcc +
        lda #$ff
        jmp scroll
+       inc crow
        jmp cmoved

moved   lda dirty           ; an edit: the steps redrawn (ui.asm)
        ora #$20
        sta dirty
        rts

; Y = the cursor's cell in the edit slot (cury * 16 + curx)
cell    lda cury
        asl a
        asl a
        asl a
        asl a
        ora curx
        tay
        rts

; the cursor's step on / off (on: the value it had last, heard)
toggle  jsr cell
        lda (ep),y
        beq +
        ldx cury                ; on -> off, remembering it
        sta lastv,x
        lda #0
        sta (ep),y
        jmp moved
+       ldx cury
        lda lastv,x
        sta (ep),y
        jsr audition
        jmp moved

; A = +1 / -1: the value of the step (switching it on if it was off)
value   sta tmp
        jsr cell
        lda (ep),y
        bne vfull
        ldx cury                ; an empty step: the cursor row's note (the
        dex                     ; one you see it on), with the last length /
        bmi vdnew               ; kind; drums: the last sound
        bne vsnew
        lda crow                ; bass
        jsr brownote
        sta tmp2
        lda lastv+1
        and #$60
        ora tmp2
        sta (ep),y
        and #$7f
        sta lastv+1
        jmp vset
vsnew   lda crow                ; singer
        jsr srowdeg
        sta tmp2
        lda lastv+2
        and #$60
        ora tmp2
        sta (ep),y
        sta lastv+2
        jmp vset
vdnew   lda lastv
        sta (ep),y
        jmp vset
vfull
+       ldx cury
        beq vdrum
        dex
        beq vbass
        and #$1f                ; singer: degree + 1, 1..16
        clc
        adc tmp
        beq vset0               ; (past either end: as it was)
        cmp #17
        bcs vset0
        sta tmp2
        lda (ep),y              ; the kind (bits 5-6) and bit 7 kept
        and #$e0
        ora tmp2
        sta (ep),y
        jmp vset
vdrum   clc                     ; drums: 1..NKIT, round
        adc tmp
        bne +
        lda #NKIT
+       cmp #NKIT+1
        bcc +
        lda #1
+       sta (ep),y
        jmp vset
vbass   and #$1f                ; bass: the next note in the scale
        sta tmp2
-       lda tmp2
        clc
        adc tmp
        beq vset0
        cmp #32
        bcs vset0
        sta tmp2
        jsr inscale
        beq -                   ; not in the scale: one more
        lda (ep),y              ; the length (bits 5-6) and the slide kept
        and #$e0
        ora tmp2
        sta (ep),y
vset    ldx cury
        lda (ep),y
        sta lastv,x
        jsr audition
vset0   jmp moved

; tmp2 = bass note 1..31: Z clear when it is in the style's scale; keeps Y
inscale lda tmp2
        clc
        adc #11                 ; pitch class relative to the root (note 13)
        tax
        lda mod12,x
        tax                     ; in the scale of the moment (the smode's)
        cpx #8                  ; (smask: bits 0-7, then smask+1 bits 0-3)
        bcs +
        lda smask
        and bit8,x
        rts
+       lda smask+1
        and bit8-8,x
        rts
bit8    .byte 1, 2, 4, 8, 16, 32, 64, 128     ; bit n

; A = +1 / -1: bass length 1-4 or the meow kind 0-3
modify  sta tmp
        jsr cell
        lda (ep),y
        beq +                   ; (an empty step, a drum: nothing)
        ldx cury
        beq +
        lda tmp                 ; bits 5-6 +- 1, round
        asl a
        asl a
        asl a
        asl a
        asl a
        and #$60
        clc
        adc (ep),y
        sta tmp2                ; (a carry into bit 7 is undone below)
        lda (ep),y
        and #$9f
        sta tmp
        lda tmp2
        and #$60
        ora tmp
        sta (ep),y
        jmp vset
+       rts

; G: the bass step's slide (bit 7) on / off
slide   ldx cury
        cpx #1
        bne +
        jsr cell
        lda (ep),y
        beq +
        eor #$80
        sta (ep),y
        jmp vset
+       rts

; A = slot to edit (F1-F7: bar A-D); setep: ep on slot eslot
editslot
        sta eslot
        jsr setep
        jsr autoview
        lda #$80
        sta dirty
        jmp status
setep   lda eslot
        jsr slotptr
        sta ep
        sty ep+1
        rts

; DEL: the cursor's row (its cat, 16 steps) cleared
clearrow
        lda cury
        asl a
        asl a
        asl a
        asl a
        tay
        ldx #16
        lda #0
-       sta (ep),y
        iny
        dex
        bne -
        jmp moved

; slot A into the slot being edited
copya   lda #0
        jsr slotptr
        sta gp
        sty gp+1
        ldy #47                 ; all three rows: 48 bytes
-       lda (gp),y
        sta (ep),y
        dey
        bpl -
        jmp moved

; the chain presets: AAAB, AABB, ABAC, ABCD, A, AB, AAABAAAC
CHAINS   = [[0,0,0,1], [0,0,1,1], [0,1,0,2], [0,1,2,3], [0], [0,1], [0,0,0,1,0,0,0,2]]
chainlen .byte 4, 4, 4, 4, 1, 2, 8               ; per preset: its length,
chainoff .byte 0, 4, 8, 12, 16, 17, 19          ; where it starts in chaindat,
chaindat .byte 0,0,0,1, 0,0,1,1, 0,1,0,2, 0,1,2,3, 0, 0,1, 0,0,0,1,0,0,0,2

; C: the next preset into the song's chain (song+4, song+5...)
nextchain
        ldx chainp
        inx
        cpx #len(CHAINS)
        bcc +
        ldx #0
+       stx chainp
        lda chainlen,x
        sta song+4
        ldy chainoff,x
        ldx #0
-       lda chaindat,y
        sta song+5,x
        iny
        inx
        cpx song+4
        bne -
        lda song+4              ; play on from the chain's start next bar
        sec
        sbc #1
        sta bar
        lda #$80
        sta dirty
        rts

; chainp = the preset matching the song's chain ($ff: its own)
findchain
        ldx #len(CHAINS)-1
-       lda chainlen,x
        cmp song+4
        bne fnext
        ldy chainoff,x
        stx tmp
        ldx #0
-       lda chaindat,y
        cmp song+5,x
        bne fno
        iny
        inx
        cpx song+4
        bne -
        ldx tmp
        stx chainp
        rts
fno     ldx tmp
fnext   dex
        bpl --
        lda #$ff
        sta chainp
        rts

; ------------------------------------------------------------------ audition
; play the cursor's step now, so you hear what you set
audition
        jsr cell
        lda (ep),y
        beq +
        ldx cury
        beq adrum
        dex
        beq abass
        ldx #0                  ; singer: no echoes
        jmp trig_sing
adrum   jmp trig_drum
abass   jsr trig_bass
        lda running
        bne +
        lda #12                 ; stopped: let it go after a while
        sta audt
+       rts

; once a frame: an auditioned bass note let go when audt runs out
audition_tick
        lda audt
        beq +
        dec audt
        bne +
        jmp bass_off
+       rts

; H: the harmony meow off / a third / a fifth (it sings on SID 2)
harmkey lda sid2
        ora sid2+1
        bne +
        ldx #<msg_nosid2
        ldy #>msg_nosid2
        jmp message
+       jsr harm_toggle         ; then the message for harmony 0 / 2 / 4
        ldx #<msg_hoff
        ldy #>msg_hoff
        lda harmony
        beq +
        ldx #<msg_h3
        ldy #>msg_h3
        cmp #2
        beq +
        ldx #<msg_h5
        ldy #>msg_h5
+       jmp message

; A = +1 / -1: the singer's transpose, in scale degrees, -7..+7
transpose
        clc
        adc transp
        cmp #8
        beq +                   ; +8: no
        cmp #$f8
        beq +                   ; -8: no
        sta transp
        jsr store3
        lda #$80
        sta dirty
+       rts

; A = +1 / -1: the bass's transpose, in scale degrees, -7..+7 (song+2's
; high nibble, over the swing)
btranspose
        clc
        adc btransp
        cmp #8
        beq +
        cmp #$f8
        beq +
        sta btransp
        asl a
        asl a
        asl a
        asl a
        sta tmp
        lda swing
        ora tmp
        sta song+2
        lda #$80
        sta dirty
+       rts

; M: the next smode (the style's own, major, minor, dorian, phrygian,
; mixolydian, lydian, blues); song+0's high nibble
nextmode
        ldx smode
        inx
        cpx #NMODES
        bcc +
        ldx #0
+       stx smode
        txa
        asl a
        asl a
        asl a
        asl a
        ora cstyle
        sta song
        jsr loadscale           ; smask (the music's now); the bass notes
        lda #1                  ; the panel shows and row 24 come in their
        sta rescp               ; own frame (infos: ui_rescale, status)
        rts

; song+3 = esteps (low nibble) and the transpose (high)
store3  lda transp
        asl a
        asl a
        asl a
        asl a
        ora esteps
        sta song+3
        rts

; ------------------------------------------------------------------ looper
; Live play: the three letter rows are pads. Q-P: the style's drum sounds
; (its own first), A-L: bass notes of the scale, Z-/: the singer's meows up
; the scale (with the meow kind and bass length last chosen). RETURN: REC on/off;
; while recording and playing, a pad is written into the bar playing,
; quantised to the nearest step (a hit late in a step lands on the next one
; and sounds there). DEL: undo the last REC pass. <-: back to editing.
; The grids follow the bar that plays.
;           q  w  e  r  t  y  u  i  o  p   a  s  d  f  g  h  j  k  l
;           z  x  c  v  b  n  m  ,  .  /
padcol  .byte 7, 1, 1, 2, 2, 3, 3, 4, 4, 5,  1, 1, 2, 2, 3, 3, 4, 4, 5
        .byte 1, 2, 2, 3, 3, 4, 4, 5, 5, 6
padrow  .byte $40,$02,$40,$02,$40,$02,$40,$02,$40,$02, $04,$20,$04,$20,$04,$20,$04,$20,$04
        .byte $10,$80,$10,$80,$10,$80,$10,$80,$10,$80
NPADS    = 29

; the live play keys (pmode on): see above
keys_live
        jsr kalone              ; (three pads at once can read as a phantom
        beq +                   ; key on the C64's matrix: SPACE, <-,
        jmp klpads              ; RETURN, DEL only when held alone)
+       #pressed K_ARROW
        beq +
        lda #0
        sta pmode
        sta rec
        sta undook              ; (live play left: no undo any more)
        jmp status
+       jsr kspace              ; (as on the matrix: play / stop, pause, the
        jsr kslots              ; slots and new sounds on the bar line, the
        jsr ktempo              ; tempo; none of them a pad)
        #pressed K_RETURN
        beq +
        jsr rectog
+       #pressed K_DEL
        beq klpads
        jsr undo
klpads  #pressed K_CRSRLR       ; CRSR right / left: the bass's transpose
        beq ++
        jsr shifted
        beq +
        lda #$ff
        jsr btranspose
        jmp ++
+       lda #1
        jsr btranspose
+       #pressed K_CRSRUD       ; CRSR up / down: the singer's transpose
        beq ++
        jsr shifted
        beq +
        lda #1
        jsr transpose
        jmp ++
+       lda #$ff
        jsr transpose
+       ldx #NPADS-1            ; every pad pressed this frame
-       ldy padcol,x
        lda knew,y
        and padrow,x
        beq +
        txa
        pha
        jsr pad
        pla
        tax
+       dex
        bpl -
        rts

; X = pad: its step byte and cat, then play / record it
pad     cpx #10
        bcs pbass
        stx tmp                 ; drums: padkit[style * 10 + pad]
        lda cstyle
        asl a
        sta tmp2
        asl a
        asl a
        adc tmp2
        adc tmp
        tay
        lda padkit,y
        ldy #0
        jmp play_rec
pbass   cpx #19
        bcs psing
        txa                     ; bass: padbass[style * 9 + pad - 10]
        sec
        sbc #10
        sta tmp
        lda cstyle
        asl a
        asl a
        asl a
        adc cstyle
        adc tmp
        tay
        lda padbass,y
        sta tmp
        lda lastv+1             ; the last length
        and #$60
        ora tmp
        ldy #1
        jmp play_rec
psing   txa                     ; singer: degree pad - 19 + 2, the last kind
        sec
        sbc #19-2-1             ; (+1: the step byte holds degree + 1)
        sta tmp
        lda lastv+2
        and #$60
        ora tmp
        ldy #2

; A = step byte, Y = cat
play_rec
        sta padv
        sty padc
        lda running
        beq pnow
        lda rec
        beq pnow
        lda step                ; the step's length in frames
        lsr a                   ; (C: an odd step, tempo - swing; even:
        lda tempo               ; tempo + swing)
        bcs +
        clc
        adc swing
        bne ++                  ; (always)
+       sec
        sbc swing
+       sta tmp                 ; length
        sec
        sbc stepcnt             ; frames gone (stepcnt: those left)
        asl a
        cmp tmp                 ; past half the step?
        bcs plate
        lda pp                  ; this step: write it, play it now
        sta gp
        lda pp+1
        sta gp+1
        lda step
        jsr pwrite
        jmp pnow
plate   lda pp                  ; the next step: the sequencer plays it
        sta gp
        lda pp+1
        sta gp+1
        lda step
        clc
        adc #1
        cmp #16
        bcc +
        lda np                  ; ...in the next bar
        sta gp
        lda np+1
        sta gp+1
        lda #0
+       jmp pwrite

; A = step: padv into cat padc's row at (gp)
pwrite  sta tmp
        lda padc
        asl a
        asl a
        asl a
        asl a
        ora tmp
        tay
        lda padv
        sta (gp),y
        lda #$80
        sta dirty
        rts

; padv on cat padc now
pnow    lda padv
        ldx padc
        stx tmp
        ldx tmp
        beq pdrum
        dex
        beq pbs
        ldx running             ; singer: echoes when the song plays
        jmp trig_sing
pdrum   jmp trig_drum
pbs     jsr trig_bass
        lda running
        bne +
        lda #12
        sta audt
+       rts

; REC on: keep the patterns for undo
rectog  lda rec
        eor #1
        sta rec
        beq +
        jsr usnap
+       jmp status

; the patterns now, for undo (the 4 slots' 192 step bytes); undo is valid
usnap   ldx #191
-       lda song+21,x
        sta undobuf,x
        dex
        cpx #$ff
        bne -
        lda #1
        sta undook
        rts

; DEL in live play: the patterns as they were when REC went on (only a
; snapshot of this song: none, or one from another song, is no undo)
undo    lda undook
        bne +
        ldx #<msg_noundo
        ldy #>msg_noundo
        jmp message
+       ldx #191
-       lda undobuf,x
        sta song+21,x
        dex
        cpx #$ff
        bne -
        lda #$80
        sta dirty
        rts
undook  .byte 0                 ; 1: undobuf holds this song's patterns

; live play: the grids show the bar playing
follow  lda pmode
        beq +
        ldx bar
        lda song+5,x
        cmp eslot
        beq +
        sta eslot
        jsr setep
        lda #$80
        sta dirty
+       rts

undobuf .fill 192               ; the patterns at REC on (rectog)


; the messages (ui.asm message: X/Y, a 0-terminated text in screen codes)
        .enc "screen"
msg_loaded .null "Loaded"
msg_noundo .null "Nothing to undo"
msg_start  .null "RUN/STOP: help     <-: live play"
msg_off    .null "Switch called off"
msg_nslot  .text "Next bar: slot "
msg_nslotn .null "1"
msg_nstyle .null "New sounds at the next bar"
msg_newslot .null "A new song in this slot"
msg_newall .null "Ten new songs"
msg_defs   .null "The ten styles' songs are back"
msg_nosid2 .null "Needs a 2nd SID"
msg_hoff   .null "Harmony off"
msg_h3     .null "Harmony: 3rd up"
msg_h5     .null "Harmony: 5th up"
        .enc "none"

; ------------------------------------------------------------------ cats
; a cat that played: the drummer plays the pose of the sound (kitpose:
; snare, hat, cymbal, kick), the bassist swaps between his two plucks; the
; singer sings while the meow lasts and flicks an ear on the echoes. Back
; to idle (0) when the time is up.
poses   lda echoev
        beq +
        lda catt+2              ; an echo while not singing: ear flick
        bne +
        ldx #2
        lda #2
        jsr cat_pose
        lda #8
        sta catt+2
+       ldx #2
pcat    lda cathit,x
        beq pidle
        ldy #0
        sty tmp
        cpx #0
        bne +
        tay                     ; drums: the pose of the sound
        lda kitpose-1,y
        sta tmp
+       lda #0
        sta cathit,x
        jsr stage_hit           ; its light flashes
        lda #6                  ; frames a hit shows
        cpx #2
        bne +
        ldy echo_k              ; the singer: as long as the meow (its kind)
        lda mlen,y
+       sta catt,x
        lda tmp
        bne +
        lda pose,x              ; 1, 2, 1, 2... (the singer stays 1)
        eor posex,x
        sta pose,x
+       jsr cat_pose
        jmp pnext
pidle   lda catt,x
        beq pnext
        dec catt,x
        bne pnext
        lda #0
        jsr cat_pose
pnext   dex
        bpl pcat
        rts
pose    .byte 2, 2, 1           ; per cat: the pose of its next hit
posex   .byte 3, 3, 0           ; ...xor this after each (2 <-> 1)

; A = semitone from C0: its name (3 characters) at (gp)
notename
        sta tmp2
        asl a
        clc
        adc tmp2                ; * 3 (< 288: the carry is the high byte)
        sta cp
        lda #0
        adc #0
        sta cp+1
        clc
        lda cp
        adc #<notenames
        sta cp
        lda cp+1
        adc #>notenames
        sta cp+1
        ldy #2
-       lda (cp),y
        sta (gp),y
        dey
        bpl -
        rts


fxvoice
fxlo
fxhi    .byte 0                 ; sfx_play is not used

        .include "sfx.asm"
        .include "pitch.asm"
        .include "seq.asm"
        .include "sid2.asm"     ; [sid2]
        .include "screen.asm"
title_area                      ; (the title: start-up only, then the song
        .include "title.asm"    ; slots' memory, below)
title_end
        .include "../gen/styles.inc"
        .include "disk.asm"
        .include "ui.asm"
        .include "slots.asm"
        .include "diskui.asm"   ; (last: its buffers follow it, not loaded)

; the song slots: over the title's code and pictures, which are done with
; when the slots fill (start: title_run, then slots_init); nothing of the
; title runs again
        .virtual title_area
slotmem .fill NSLOTS * SLOTLEN
slotend
        .endv
        .cerror slotend > title_end, "the song slots must fit in the title's room"

        .cerror * > $c000, "program runs into the screen at $c000"

; the stage's bitmap (tools/screen.py): the file's last part, copied to
; $e000 at start; its room is then the disk buffers' and the screen's
stage_data
        .binary "../gen/stage.bin"
        .cerror * - stage_data != STAGE_LEN, "build/stage.bin: not 3840 bytes"
        .cerror * > $d000, "the stage's bitmap runs into the I/O at $d000"
