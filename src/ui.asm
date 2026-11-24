; ------------------------------------------------------------------ the panel
; The lower half of the screen (rows 12-24) in Scrap / Genesis Project's UI
; Font V2 (art/uifont), one cat at a time:
;
;   rows 12-14 tabs: Drums | Bass | Meows, then play/pause, stop, record
;              and the tempo ( - bpm + ); the ▼ on row 14 is the playhead
;   rows 15-21 the open cat's bar as a matrix, 16 steps (step s at column
;              7 + 2s), 7 rows:
;                drums   a row per pair of sounds: roles 1-14, a left and a
;                        right one (909 names), one hit per step
;                bass    the notes of the scale (a window of 7, scrolls)
;                singer  the scale degrees (a window of 7, scrolls)
;   row 22     the frame's bottom line; the disk icon at 37 opens the disk
;              page (diskui.asm, also S / L)
;   row 23     the open cat's settings (or a message, or live play's keys)
;   row 24     style, mode, bars A-D (the one edited cyan), the chain
;              (the bar playing yellow); RUN/STOP: the help card
;
; The stage (rows 0-11) keeps screen.asm's charset ($c800); a raster
; interrupt at line 146 (row 11's last line) switches to the UI font at
; $e000 (RAM under the KERNAL: in bank 3 the VIC sees RAM there) and one at
; line 252 switches back. The same two interrupts lend sprite 7 (the mic)
; to the mouse pointer below the stage. The main loop still polls line $fa.
;
; Mouse: a 1351 (the C64 Ultimate's USB mouse) in port 1. Its buttons sit on
; the keyboard's row lines, so the keyboard is not scanned while one is held
; (as for joystick 2). Moving it moves the edit cursor over the matrix; a
; left / right click does the cell's left / right job:
;   drums   the row's left / right sound (the same one again: off)
;   bass    a note / a note sliding in (on a note: left off, right length)
;   singer  a meow of the kind chosen on row 23 (on one: left off, right
;           the next kind)
; Keys: RETURN = left, SHIFT+RETURN = right, C= the next cat, CRSR moves.
; Test hook: ui_fake (mouse_fake), for c64bridge, which has no mouse.

UI_CHARSET  = $e000
D018_STAGE  = $02           ; screen $c000, charset $c800
D018_UI     = $08           ; screen $c000, charset $e000
SPLIT_LINE  = 146           ; the last line of row 11
BOTTOM_LINE = 252
PTR_BLOCK   = $1f           ; sprite block $1f ($c7c0): the pointer
PTR_DATA    = SCR_SPRITES + (PTR_BLOCK - $10) * 64

HEADROW  = 14               ; the playhead's row
MROW     = 15               ; the matrix's top row
MCOL     = 7                ; step 0's column
SETROW   = 23
STROW    = 24
NROWS    = 7
COLOFS   = >(SCR_COLRAM - SCR_SCREEN)

; UI font glyphs (bold $00-$7f, regular +$80)
G_H     = $40
G_V     = $5d
G_STL   = $70
G_STR   = $6e
G_SBL   = $6d
G_SBR   = $7d
G_TT    = $72
G_BT    = $71
G_LT    = $6b
G_RT    = $73
G_PLAY  = $e1
G_STOP  = $fc
G_REC   = $fb
G_PAUSE = $ec
G_UP    = $e2
G_DOWN  = $62
G_DOT   = $65               ; an empty step
G_BOX   = $e8               ; the cursor on an empty step
G_FULL  = $60               ; a left drum sound, a bass note
G_BALL  = $fb               ; a right drum sound, a mew
G_HEART = $f0               ; a meow
G_RING  = $5c               ; an ooh
G_ARROW = $e9               ; a bass note sliding in
G_SUST  = $f6               ; a bass note holding
G_SL_L0 = $75               ; slider: left cap (empty, filled), fill, knob,
G_SL_L1 = $f4               ; empty track, right cap
G_SL_F  = $f6
G_SL_K  = $f5
G_SL_E  = $c0
G_SL_R  = $76
G_DISK  = $6f               ; the disk icon (row 22)

C_BLK = 0
C_WHT = 1
C_RED = 2
C_CYN = 3
C_PUR = 4
C_GRN = 5
C_BLU = 6
C_YEL = 7
C_ORA = 8
C_BRN = 9
C_LRD = 10
C_DGR = 11
C_GRY = 12
C_LGN = 13
C_LBL = 14
C_LGR = 15

; the regular weight: letters + $80
        .enc "uireg"
        .cdef "  ", $20
        .cdef "az", $81
        .cdef "AZ", $c1
        .cdef "09", $b0
        .cdef "!/", $a1
        .cdef ":?", $ba
        .enc "none"

; ------------------------------------------------------------------ init
; after screen_init: the font, the pointer, the panel, the interrupts
ui_init
        sei
        lda #<uifont            ; 2K of font to $e000 (writes go to the RAM)
        sta gp
        lda #>uifont
        sta gp+1
        lda #<UI_CHARSET
        sta cp
        lda #>UI_CHARSET
        sta cp+1
        ldx #8
        ldy #0
-       lda (gp),y
        sta (cp),y
        iny
        bne -
        inc gp+1
        inc cp+1
        dex
        bne -
        ldx #NCUSTG-1           ; our own glyphs over unused ones of the font:
-       lda custgc,x            ; the floppy (4 x 4) and the panel's disk icon
        sta gp
        lda #0
        sta gp+1
        .rept 3
        asl gp
        rol gp+1
        .next
        clc
        lda gp+1
        adc #>UI_CHARSET
        sta gp+1
        txa
        asl a
        asl a
        asl a
        tay
        sty tmp
        ldy #0
-       sty tmp2
        ldy tmp
        lda custg,y
        inc tmp
        ldy tmp2
        sta (gp),y
        iny
        cpy #8
        bne -
        dex
        bpl --
        ldx #63                 ; the pointer's sprite block
-       lda ptrspr,x
        sta PTR_DATA,x
        dex
        bpl -
        lda $d00e               ; sprite 7 as screen_init placed it
        sta s7x
        lda $d00f
        sta s7y
        lda $d010
        sta s7hi
        lda $d01c
        sta s7mc
        lda $d01d
        sta s7xe
        lda $d017
        sta s7ye
        lda #$80                ; no VU meters: the panel is ours
        sta screen_novu
        lda #0
        sta mfirst
        jsr ui_draw
        ; fall through

; the split interrupts on (also after disk I/O)
ui_irqon
        sei
        lda #<irq_split
        sta $0314
        lda #>irq_split
        sta $0315
        lda $d011
        and #$7f
        sta $d011
        lda #SPLIT_LINE
        sta $d012
        lda #1
        sta $d01a
        sta $d019
        lda #0
        sta mfirst              ; the mouse's next reading is no move
        cli
        rts

; and off, the KERNAL's IRQ handler back (around disk I/O)
ui_irqoff
        sei
        lda #0
        sta $d01a
        lda #1
        sta $d019
        lda #<$ea31
        sta $0314
        lda #>$ea31
        sta $0315
        lda #D018_STAGE
        sta $d018
        rts

; line 146: the charset changes after the line's last character (cycle 56
; on). We get here 36-45 cycles into the line (the KERNAL's $ff48 entry
; included); the write lands 22 later: cycles 58-67 (67 = line 147's 4th,
; before the badline's character fetches)
irq_split
        ldx #3
-       dex
        bne -
        lda #D018_UI
        sta $d018
        lda mseen               ; the pointer: sprite 7 below the stage
        beq irql9
        lda SCR_SCREEN + $3ff
        sta s7ptr
        lda $d02e
        sta s7col
        lda #PTR_BLOCK
        sta SCR_SCREEN + $3ff
        lda #C_WHT
        sta $d02e
        lda mx
        clc
        adc #24
        sta $d00e
        lda mx+1
        adc #0
        lsr a                   ; C = bit 8
        lda s7hi
        and #$7f
        bcc irqs1
        ora #$80
irqs1   sta $d010
        lda my
        clc
        adc #50
        sta $d00f
        lda s7mc
        and #$7f
        sta $d01c
        lda s7xe
        and #$7f
        sta $d01d
        lda s7ye
        and #$7f
        sta $d017
        lda #1
        sta s7lent
irql9   lda #<irq_bottom
        sta $0314
        lda #>irq_bottom
        sta $0315
        lda #BOTTOM_LINE
        sta $d012
        lda #1
        sta $d019
        jmp $ea81

; line 252: the stage's charset and sprite 7 back for the next frame
irq_bottom
        lda #D018_STAGE
        sta $d018
        lda s7lent
        beq +
        lda #0
        sta s7lent
        lda s7x
        sta $d00e
        lda s7y
        sta $d00f
        lda s7hi
        sta $d010
        lda s7mc
        sta $d01c
        lda s7xe
        sta $d01d
        lda s7ye
        sta $d017
        lda s7ptr
        sta SCR_SCREEN + $3ff
        lda s7col
        sta $d02e
+       lda #<irq_split
        sta $0314
        lda #>irq_split
        sta $0315
        lda #SPLIT_LINE
        sta $d012
        lda #1
        sta $d019
        jmp $ea81

s7x     .byte 0
s7y     .byte 0
s7hi    .byte 0
s7mc    .byte 0
s7xe    .byte 0
s7ye    .byte 0
s7ptr   .byte 0
s7col   .byte 0
s7lent  .byte 0             ; sprite 7 is the pointer until line 252

; ------------------------------------------------------------------ mouse
; once a frame from input, before the keyboard: the 1351 in port 1
; (selected since the end of the last frame's input, so POTX / POTY are
; settled). Moves, hovers, clicks. Out: C set while a port 1 line is held
; (no keyboard scan then).
mouse_read
        lda mfirst
        cmp #2
        bcs +
        inc mfirst              ; (the first readings after start-up or disk
        lda $d419               ; I/O: only remembered)
        sta mpx
        lda $d41a
        sta mpy
        jmp mbuttons
+       lda mseen               ; asleep: the POTs of a port without a mouse
        bne mrawake             ; drift slowly, so the pointer wakes on a
        lda $d419               ; click or a quick move (4+ in a frame)
        ldy mpx
        sta mpx
        jsr mdelta
        jsr mabs
        sta tmp
        lda $d41a
        ldy mpy
        sta mpy
        jsr mdelta
        jsr mabs
        clc
        adc tmp
        cmp #4
        bcc +
        lda #1
        sta mseen
+       jmp mbuttons
mrawake lda $d419
        ldy mpx
        sta mpx
        jsr mdelta
        beq +
        ldx #0                  ; x += the move (signed)
        ora #0
        bpl mr1
        dex
mr1     clc
        adc mx
        sta mx
        txa
        adc mx+1
        sta mx+1
        inc mmoved
+       lda $d41a
        ldy mpy
        sta mpy
        jsr mdelta
        beq +
        sta tmp                 ; y -= the move (the mouse's up is +)
        lda my
        sec
        sbc tmp
        sta my
        inc mmoved
+       jsr mclamp
        lda mmoved
        beq mbuttons
        lda #0
        sta mmoved
        jsr mhover
mbuttons
        lda #$ff                ; the buttons: port 1's fire (left) and up
        sta $dc00               ; (right) lines, no keyboard column driven
        lda $dc01
        eor #$ff
        and #$1f
        sta mheld
        and #$11                ; left = bit 4, right = bit 0
        tax
        eor mbut                ; changed...
        stx mbut
        and mbut                ; ...and held: pressed now
        beq +
        ldx mseen
        bne mwake
        inc mseen               ; asleep: the click only wakes the pointer
        bne +
mwake   and #$10
        beq mright
        lda #0                  ; left
        jsr ui_click
        jmp +
mright  lda #1
        jsr ui_click
+       lda mheld               ; held: no keys
        cmp #1
        rts

; A = signed -> A = |A|
mabs    ora #0
        bpl +
        eor #$ff
        clc
        adc #1
+       rts

; A = new POT value, Y = old: A = the signed move (the 1351's way), Z set
; when none
mdelta  sty mold
        sec
        sbc mold
        and #$7f
        cmp #$40
        bcs +
        lsr a
        rts
+       ora #$c0
        cmp #$ff
        beq +
        sec
        ror a
        rts
+       lda #0
        rts

; x 0-319, y 104-199 (rows 13-24: the pointer never goes over the stage)
mclamp  lda mx+1
        bpl +
        lda #0
        sta mx
        sta mx+1
+       lda mx+1
        beq +
        lda mx
        cmp #<319
        bcc +
        lda #<319
        sta mx
        lda #>319
        sta mx+1
+       lda my
        cmp #104
        bcs +
        lda #104
        sta my
+       cmp #200
        bcc +
        lda #199
        sta my
+       rts

; mx, my -> X = column, Y = row
mcell   lda mx+1
        lsr a
        lda mx
        ror a
        lsr a
        lsr a
        tax
        lda my
        lsr a
        lsr a
        lsr a
        tay
        rts

; the pointer moved: over the matrix the cursor follows it
mhover  lda tweakon
        ora diskon
        bne mh9
        jsr mcell
        cpy #MROW
        bcc mh9
        cpy #MROW+NROWS
        bcs mh9
        cpx #MCOL
        bcc mh9
        txa
        sec
        sbc #MCOL
        lsr a
        cmp #16
        bcc +
        lda #15
+       sta curx
        tya
        sec
        sbc #MROW
        sta crow
        jmp cmoved
mh9     rts

; the test hook: set mx / my, then ui_fake = 1 a left click, 2 a right
; click, 3 a move; done in the next frame
mouse_fake
        lda ui_fake
        beq +
        ldx #0
        stx ui_fake
        pha
        lda #1
        sta mseen
        jsr mclamp
        jsr mhover
        pla
        cmp #3
        bcs +
        sbc #0                  ; (C clear: -1) 0 left, 1 right
        jmp ui_click
+       rts

mx      .word 160
my      .byte 176
mpx     .byte 0
mpy     .byte 0
mold    .byte 0
mbut    .byte 0
mheld   .byte 0
mmoved  .byte 0
mfirst  .byte 0
mseen   .byte 0             ; the mouse was used: show the pointer
ui_fake .byte 0

; ------------------------------------------------------------------ clicks
; A = 0 left, 1 right: at the pointer's cell
ui_click
        sta side
        jsr mcell
        stx ccol
        lda helpon              ; the help up: a click closes it
        beq +
        jmp help_close
+       lda diskon              ; the disk page (diskui.asm)
        beq +
        jmp dclick
+       cpy #MROW
        bcs +
        jmp ctop
+       cpy #MROW+NROWS
        bcc +
        jmp cbottom
+       lda tweakon
        beq +
        jmp tclick
+       lda dirty               ; (a full redraw still to come: the screen
        bpl +                   ; isn't the matrix yet, so no click on it)
        rts
+       cpx #MCOL               ; the matrix: the cells edit, column 38
        bcc c9                  ; scrolls
        cpx #38
        bcc +
        cpy #MROW
        beq cscrup
        cpy #MROW+NROWS-1
        beq cscrdn
c9      rts
+       jsr mhover
        lda side
        jmp act
cscrup  lda #1
        jmp scroll
cscrdn  lda #$ff
        jmp scroll

ctop    ldx #0                  ; the tab bar (rows 13-14)
-       lda ccol
        cmp hitx0,x
        bcc ct9
        cmp hitx1,x
        bcc +
        inx
        cpx #NHITS
        bne -
ct9     rts
+       lda hitlo,x
        sta gp
        lda hithi,x
        sta gp+1
        jmp (gp)

; the tab bar's buttons: columns from - to (not included)
NHITS   = 8
hitx0   .byte 1, 7, 12, 19, 23, 27, 31, 37
hitx1   .byte 6, 11, 18, 22, 26, 30, 35, 40
hitlo   .byte <tab_drums, <tab_bass, <tab_sing, <b_play, <b_stop, <b_rec, <b_slower, <b_faster
hithi   .byte >tab_drums, >tab_bass, >tab_sing, >b_play, >b_stop, >b_rec, >b_slower, >b_faster

tab_drums
        ldx #0
        beq tabclk
tab_bass
        ldx #1
        bne tabclk
tab_sing
        ldx #2
tabclk  lda side                ; right: the cat muted / back
        bne mutetog
        cpx lane                ; left on another tab: open it
        bne tcopen
        lda tweakon             ; left on the open one: its settings page

        bne +
        jmp tweak_open
+       jmp tweak_close
tcopen  txa
        jmp settab

; X = cat: muted / back; muting cuts its sound (the singer's echoes and
; harmony too)
mutetog lda mute,x
        eor #1
        sta mute,x
        beq mt9
        lda mvoice,x
        jsr vsilent
        cpx #2
        bne mt9
        lda #0
        sta echo_n
        lda sid2+1              ; SID 2: its echo and harmony voices
        beq mt9
        lda #3
        jsr vsilent
        lda #4
        jsr vsilent
mt9     jmp tdirty
mvoice  .byte 2, 0, 1           ; drums voice 3, bass 1, singer 2

; A = voice: its script stopped, its gate off (keeps X)
vsilent stx vsx
        tax
        lda #0
        sta sptrh,x
        lda ctl,x
        and #$fe
        sta ctl,x
        ldy sidoff,x
        sta $d404,y
        ldx vsx
        rts
vsx     .byte 0
b_play  lda running             ; play / pause (on from where it was)
        eor #1
        sta running
        bne +
        jmp sfx_stop
+       rts
b_stop  lda #0                  ; stop: back to the top of the song
        sta running
        jsr sfx_stop
        jsr seq_apply
        lda rec
        beq +
        jsr rectog
+       lda #0
        sta pmode
        jmp status
b_rec   lda rec                 ; record: live play with REC on, or all off
        beq +
        jsr rectog
        lda #0
        sta pmode
        jmp status
+       lda #1
        sta pmode
        jmp rectog
b_slower
        lda tempo
        cmp #15
        bcs +
        inc tempo
        jmp retempo
+       rts
b_faster
        lda tempo
        cmp #5
        bcc +
        dec tempo
        jmp retempo
+       rts

cbottom cpy #SETROW
        bne +
        jmp csettings
+       cpy #STROW
        beq +
        cpx #36                 ; row 22: the disk icon (36-38) opens the
        bcc cb9                 ; disk page
        cpx #39
        bcs cb9
        jmp disk_open
cb9     rts
+       lda ccol                ; row 24: style, mode, bars, chain
        cmp #12
        bcs cb2
        lda side                ; the slot: left the next one, right the
        beq +                   ; style list (again: closed) (slots.asm)
        lda spick
        beq cbpick
        jmp tweak_close
cbpick  jmp pick_open
+       ldx pslot               ; (after the one waiting, if any)
        dex
        bpl +
        ldx curslot
+       inx
        cpx #NSLOTS
        bcc +
        ldx #0
+       txa
        jmp slot_select
cb2     cmp #17
        bcs +
        jmp nextmode
+       cmp #21                 ; the bars A-D at 17-20
        bcs +
        sbc #17-1               ; (C clear: -17)
        jmp editslot
+       cmp #22
        bne +
        jmp chainless           ; -
+       cmp #23
        bne +
        jmp chainmore           ; +
+       bcc +
        sbc #CHAINCOL           ; a bar of the chain: the next slot (right:
        cmp song+4              ; the one before)
        bcs +
        tax
        lda song+5,x
        ldy side
        bne cbprev
        adc #1                  ; (C clear)
        and #3
        jmp cbset
cbprev  sec
        sbc #1
        and #3
cbset   sta song+5,x
        jmp chained
+       rts

; the chain one bar shorter (1 at least) / longer (16 at most; the new
; bar plays the last one's slot again)
chainless
        ldx song+4
        cpx #2
        bcc +
        dex
        stx song+4
        lda bar                 ; the bar playing gone: it is the last one
        cmp song+4              ; now (the next goes back to the top)
        bcc chained
        dex
        stx bar
        jmp chained
chainmore
        ldx song+4
        cpx #16
        bcs +
        lda song+5-1,x
        sta song+5,x
        inc song+4
chained jsr findchain           ; (a preset again? C goes on from it)
        jsr songline
        lda #$80
        sta dirty
+       rts

csettings
        lda msgt                ; row 23 reacts only to what it shows: not
        bne cs9                 ; under a message or live play's keys
        lda tweakon             ; the tweaks page: "T back" (33-38) closes it
        beq cs1
        lda ccol
        cmp #33
        bcc +
        cmp #39
        bcs cs9
        jmp tweak_close
+       cmp #23                 ; [ ] Preview (23-31)
        bcc cs9
        cmp #32
        bcs cs9
        jmp heartog
cs1     lda pmode
        bne cs9
        ldx lane
        beq setdrums
        dex
        beq setbass
        jmp setsing
cs9     rts

; drums: the swing slider, columns 6 (0) to 13 (6)
setdrums
        lda ccol
        cmp #6
        bcc sd9
        cmp #14
        bcs sd9
        sec
        sbc #7
        bcs +
        lda #0
+       jmp setswing
sd9     rts

; bass: key - (4), + (9); the length new notes get (12-16)
setbass lda ccol
        cmp #4
        bne +
        lda #$ff
        jmp btranspose
+       cmp #9
        bne +
        lda #1
        jmp btranspose
+       cmp #12
        bcc +
        cmp #17
        bcs +
        lda lastv+1             ; 1-4, round
        clc
        adc #$20
        and #$60
        sta tmp
        lda lastv+1
        and #$9f
        ora tmp
        sta lastv+1
        jmp sdirty
+       rts

; singer: the echo slider 5 (off) - 11; key - (17), + (22); the harmony
; (25-32); the kind new meows get (33, 35, 37, 39)
setsing lda ccol
        cmp #5
        bcc ss9
        cmp #12
        bcs ss2
        sec
        sbc #6
        bcs +
        lda #0
+       tax
        lda echos,x
        sta esteps
        jsr store3
        jsr seq_retempo
        jmp sdirty
ss2     cmp #17
        bne +
        lda #$ff
        jmp transpose
+       cmp #22
        bne +
        lda #1
        jmp transpose
+       cmp #25
        bcc ss9
        cmp #33
        bcs +
        jmp harmkey
+       sec
        sbc #33
        bcc ss9
        lsr a
        cmp #4
        bcs ss9
        ldx side                ; right: the tweaks page, on its row
        beq +
        pha
        jsr tweak_open
        pla
        sta tmp
        asl a
        adc tmp
        sta tsel
        rts
+       asl a                   ; the kind into bits 5-6 of the last meow
        asl a
        asl a
        asl a
        asl a
        sta tmp
        lda lastv+2
        and #$9f
        ora tmp
        sta lastv+2
        jmp sdirty
ss9     rts

; A = swing 0-6 (kept under the tempo); song+2's low nibble
setswing
        cmp tempo
        bcc +
        lda tempo
        sec
        sbc #1
+       sta swing
        sta tmp
        lda song+2
        and #$f0
        ora tmp
        sta song+2
        jmp sdirty

; ------------------------------------------------------------------ editing
; A = 0 left, 1 right: the cursor's cell (curx, crow) in the open cat's row
act     sta side
        lda tweakon             ; (never under a page, the disk page or help)
        ora diskon
        ora helpon
        beq +
        rts
+       jsr cell                ; Y = lane * 16 + curx
        ldx lane
        beq actdrum
        dex
        beq actbass
        jmp actsing

actdrum lda crow                ; role = row * 2 + side + 1
        asl a
        sec
        adc side
        cmp (ep),y
        bne +
        lda #0                  ; the same sound again: off
+       sta (ep),y
        beq +
        sta lastv
        jsr audition
+       jmp moved

actbass lda (ep),y
        beq abnew
        jsr browof              ; a note on this row?
        cmp crow
        bne abnew
        lda side
        bne +
        lda (ep),y              ; left: off
        and #$7f
        sta lastv+1
        lda #0
        sta (ep),y
        jmp moved
+       lda (ep),y              ; right: the length 1-4, round
        clc
        adc #$20
        and #$60
        sta tmp
        lda (ep),y
        and #$9f
        ora tmp
        sta (ep),y
        and #$7f
        sta lastv+1
        jsr audition
        jmp moved
abnew   lda crow                ; a new note: the row's, the last length,
        jsr brownote            ; sliding in on the right button
        sta tmp
        lda lastv+1
        and #$60
        ora tmp
        ldx side
        beq +
        ora #$80
+       sta (ep),y
        and #$7f
        sta lastv+1
        jsr audition
        jmp moved

actsing lda (ep),y
        beq asnew
        jsr srowof
        cmp crow
        bne asnew
        lda side
        bne +
        lda (ep),y              ; left: off
        sta lastv+2
        lda #0
        sta (ep),y
        jmp moved
+       lda (ep),y              ; right: the next kind
        clc
        adc #$20
        and #$60
        sta tmp
        lda (ep),y
        and #$9f
        ora tmp
        sta (ep),y
        sta lastv+2
        jsr audition
        jmp moved
asnew   lda crow                ; a meow on the row's degree, the last kind
        jsr srowdeg
        sta tmp
        lda lastv+2
        and #$60
        ora tmp
        sta (ep),y
        sta lastv+2
        jsr audition
        jmp moved

; A = +1 / -1: scroll the open cat's window (bass, singer)
scroll  ldx lane
        beq scr9
        clc
        adc view-1,x
        bmi scr9
        cpx #1
        bne +
        cmp bmaxv
        beq scrok
        bcs scr9
        bcc scrok
+       cmp #16-NROWS+1
        bcs scr9
scrok   sta view-1,x
        jmp sdirty
scr9    rts

; C=: the next cat; settab: A = cat, open its tab
nexttab ldx lane
        inx
        cpx #3
        bcc +
        ldx #0
+       txa
settab  sta lane
        lda #0
        sta tweakon
        jsr autoview
        jmp tdirty

; ------------------------------------------------------------------ rows
; the bass's rows: the notes 1-31 in the scale of the moment (bscale,
; bcount of them); brow[n] = the index of the last one <= n (bit 7: n is
; off the scale). The window shows 7 from view (its bottom row).
ui_rescale
        lda #0
        sta bcount
        lda #1
        sta tmp2
-       jsr inscale             ; (tmp2; changes X, keeps Y)
        php
        ldx bcount
        plp
        beq +
        lda tmp2
        sta bscale,x
        inx
        stx bcount
+       ldy bcount
        dey
        tya
        bpl +
        lda #0
+       ldx tmp2
        sta brow,x
        lda bcount
        beq +
        ldy bcount
        lda bscale-1,y
        cmp tmp2
        beq +
        lda brow,x              ; off the scale
        ora #$80
        sta brow,x
+       inc tmp2
        lda tmp2
        cmp #32
        bne -
        lda bcount
        sec
        sbc #NROWS
        bcs +
        lda #0
+       sta bmaxv
        lda view
        cmp bmaxv
        bcc +
        lda bmaxv
        sta view
+       rts

; A = bass step byte -> A = its row 0-6 ($ff: not in the window), keeps Y
browof  and #$1f
        tax
        lda brow,x
        and #$7f
        sec
        sbc view
        bcc +
        cmp #NROWS
        bcs +
        eor #$ff                ; 6 - it
        clc
        adc #NROWS
        rts
+       lda #$ff
        rts

; A = row 0-6 -> A = the row's bass note, keeps Y
brownote
        eor #$ff
        sec
        adc #NROWS-1            ; 6 - row
        clc
        adc view
        cmp bcount
        bcs +
        tax
        lda bscale,x
        rts
+       lda #13
        rts

; A = singer step byte -> its row 0-6 ($ff: not in the window), keeps Y
srowof  and #$1f
        sec
        sbc #1                  ; the degree 0-15
        sec
        sbc view+1
        bcc +
        cmp #NROWS
        bcs +
        eor #$ff
        clc
        adc #NROWS
        rts
+       lda #$ff
        rts

; A = row -> A = the row's singer step bits: degree + 1, keeps Y
srowdeg eor #$ff
        sec
        adc #NROWS-1
        clc
        adc view+1
        clc
        adc #1
        rts

; the window over the open cat's notes: the lowest at the bottom
autoview
        ldx lane
        beq av9
        lda #$ff
        sta tmp2
        ldy #15
avloop  tya
        pha
        jsr cell1
        lda (ep),y
        beq avnext
        and #$1f
        ldx lane
        cpx #1
        bne avs
        tax                     ; bass: its place in the scale
        lda brow,x
        and #$7f
        jmp avmin
avs     sec                     ; singer: the degree
        sbc #1
avmin   cmp tmp2
        bcs avnext
        sta tmp2
avnext  pla
        tay
        dey
        bpl avloop
        lda tmp2
        cmp #$ff
        bne avset
        lda #0                  ; nothing: the bass from its root, the
        ldx lane                ; singer from the bottom
        cpx #1
        bne avset
        ldx #13
        lda brow,x
        and #$7f
avset   ldx lane
        cpx #1
        bne avsing
        cmp bmaxv
        bcc +
        lda bmaxv
+       sta view
        jmp avcur
avsing  cmp #16-NROWS+1
        bcc +
        lda #16-NROWS
+       sta view+1
avcur   lda #NROWS-1
        sta crow
av9     rts

; Y = step 0-15 -> Y = the open cat's cell
cell1   lda lane
        asl a
        asl a
        asl a
        asl a
        sta ctmp
        tya
        ora ctmp
        tay
        rts

lane    = cury                  ; the open cat (what was the cursor's row)
crow    .byte 6                 ; the cursor's matrix row 0-6
view    .byte 0, 0              ; the bottom row's index: bass, singer
bmaxv   .byte 0
bcount  .byte 0
side    .byte 0
ccol    .byte 0
ctmp    .byte 0
mrw     .byte 0
bscale  .fill 32
brow    .fill 32

; ------------------------------------------------------------------ drawing
; rows 12-24 from scratch
ui_draw jsr ui_rescale
        ldx #0                  ; clear rows 12-24 (520 cells)
-       lda #$20
        .for r = 0, r < 520, r += 130
        sta SCR_SCREEN + 12*40 + r,x
        .next
        lda #C_LGR
        .for r = 0, r < 520, r += 130
        sta SCR_COLRAM + 12*40 + r,x
        .next
        inx
        cpx #130
        bne -
        ldx #38                 ; the frame: top and bottom lines, corners
-       lda #G_H
        sta SCR_SCREEN + 12*40,x
        sta SCR_SCREEN + 22*40,x
        dex
        bne -
        lda #G_STL
        sta SCR_SCREEN + 12*40
        lda #G_STR
        sta SCR_SCREEN + 12*40 + 39
        lda #G_SBL
        sta SCR_SCREEN + 22*40
        lda #G_SBR
        sta SCR_SCREEN + 22*40 + 39
        ldx #NSEPS-1            ; ┬ │ at the tab bar's separators
-       ldy tabsep,x
        lda #G_TT
        sta SCR_SCREEN + 12*40,y
        lda #G_V
        sta SCR_SCREEN + 13*40,y
        dex
        bpl -
        lda #G_V                ; the sides
        sta SCR_SCREEN + 13*40
        sta SCR_SCREEN + 13*40 + 39
        ldx #MROW+NROWS-1
-       lda rowlo,x
        sta gp
        lda rowhi,x
        sta gp+1
        lda #G_V
        ldy #0
        sta (gp),y
        ldy #39
        sta (gp),y
        dex
        cpx #MROW
        bcs -
        lda #G_DISK             ; the disk icon on the bottom line
        sta SCR_SCREEN + 22*40 + 37
        lda #C_LBL
        sta SCR_COLRAM + 22*40 + 37
        lda #$20
        sta SCR_SCREEN + 22*40 + 36
        sta SCR_SCREEN + 22*40 + 38
        lda #$80
        sta dirty
        lda #$ff
        sta lstep2
        sta cursat
        sta lbar
        jsr tabbar
        jmp status

NSEPS   = 6
tabsep  .byte 6, 11, 18, 22, 26, 30

; the tab bar (rows 13-14): the cats' names, the transport, the tempo
tabbar  ldx #2
tb1     ldy tabcol,x            ; the names: the open one bold, in its colour;
        lda tablen,x            ; a muted cat's red
        sta tmp2
        lda #C_GRY
        cpx lane
        bne +
        lda lanecol,x
+       ldy mute,x
        beq +
        lda #C_LRD
+       sta tbc
        ldy tabcol,x
tb2     lda tabtext,y           ; (the text is laid out at its columns)
        cpx lane
        beq +
        ora #$80
+       sta SCR_SCREEN + 13*40,y
        lda tbc
        sta SCR_COLRAM + 13*40,y
        iny
        dec tmp2
        bne tb2
        dex
        bpl tb1
        ldx #39                 ; row 14: ├──┴──┤, open under the tab
-       lda #G_H
        sta SCR_SCREEN + 14*40,x
        lda #C_LGR
        sta SCR_COLRAM + 14*40,x
        dex
        bpl -
        lda #G_LT
        sta SCR_SCREEN + 14*40
        lda #G_RT
        sta SCR_SCREEN + 14*40 + 39
        ldx #NSEPS-1
-       ldy tabsep,x
        lda #G_BT
        sta SCR_SCREEN + 14*40,y
        dex
        bpl -
        ldx lane                ; the gap under the open tab, ┘ └ at its ends
        ldy tabcol,x
        dey
        lda #G_SBR
        cpx #0
        bne +
        lda #G_V
+       sta SCR_SCREEN + 14*40,y
        iny
        lda tablen,x
        sta tmp2
        lda #$20
-       sta SCR_SCREEN + 14*40,y
        iny
        dec tmp2
        bne -
        lda #G_SBL
        sta SCR_SCREEN + 14*40,y
        ldx #39
-       lda SCR_SCREEN + 14*40,x
        sta r14buf,x
        dex
        bpl -
        lda #$ff
        sta lstep2
        ; fall through

; the transport's state and the tempo
transport
        lda running
        beq +
        lda #G_PAUSE
        ldx #C_GRN
        bne ++
+       lda #G_PLAY
        ldx #C_WHT
+       sta SCR_SCREEN + 13*40 + 20
        stx SCR_COLRAM + 13*40 + 20
        lda #G_STOP
        sta SCR_SCREEN + 13*40 + 24
        lda #C_LGR
        sta SCR_COLRAM + 13*40 + 24
        lda #G_REC
        sta SCR_SCREEN + 13*40 + 28
        ldx #C_LRD
        lda rec
        beq +
        ldx #C_RED
        lda frame
        and #16
        beq +
        ldx #C_WHT
+       stx SCR_COLRAM + 13*40 + 28
        lda #$2d                ; - bpm +
        sta SCR_SCREEN + 13*40 + 32
        lda #$2b
        sta SCR_SCREEN + 13*40 + 38
        lda #C_WHT
        sta SCR_COLRAM + 13*40 + 32
        sta SCR_COLRAM + 13*40 + 38
        ldx tempo
        lda bpm100-4,x
        sta SCR_SCREEN + 13*40 + 34
        lda bpm10-4,x
        sta SCR_SCREEN + 13*40 + 35
        lda bpm1-4,x
        sta SCR_SCREEN + 13*40 + 36
        lda #C_YEL
        sta SCR_COLRAM + 13*40 + 34
        sta SCR_COLRAM + 13*40 + 35
        sta SCR_COLRAM + 13*40 + 36
        lda running
        sta ltrans
        lda rec
        sta ltrans+1
        lda tempo
        sta ltrans+2
        rts
ltrans  .byte 0, 0, 0
tbc     .byte 0

; a step lasts tempo frames (50 Hz, 4 steps a beat): 750 / tempo bpm
bpm100  .for t = 4, t < 16, t += 1
        .byte ((1500 / t + 1) / 2 < 100) ? $20 : $30 + (1500 / t + 1) / 2 / 100
        .next
bpm10   .for t = 4, t < 16, t += 1
        .byte $30 + (1500 / t + 1) / 2 / 10 % 10
        .next
bpm1    .for t = 4, t < 16, t += 1
        .byte $30 + (1500 / t + 1) / 2 % 10
        .next

        .enc "screen"
tabtext .text " Drums Bass Meows "
        .enc "none"
tabcol  .byte 1, 7, 12
tablen  .byte 5, 4, 6               ; (Meows + a blank: the gap meets the wall at 18)
lanecol .byte C_WHT, C_ORA, C_LBL

; ------------------------------------------------------------------ the matrix
ui_matrix
        lda tweakon             ; (the meow tweaks page instead)
        beq +
        jmp ui_tweak
+       lda #1                  ; all of columns 1-38, then the labels
        jsr mgrid
        lda #0
        sta mrw
mrow1   lda mrw                 ; a row's labels
        jsr rowptr
        ldx lane
        beq mldrum
        dex
        beq mlbass
        lda mrw                 ; singer: the note of the degree
        jsr srowdeg
        clc
        adc #3
        clc
        adc transp
        bpl +
        lda #2
+       cmp #2
        bcs +
        lda #2
+       cmp #30
        bcc +
        lda #29
+       tax
        lda degtab,x
        ldx #C_LGR
        jmp mlname
mlbass  lda mrw                 ; bass: the note the row plays
        jsr brownote
        cmp #13
        php
        jsr bassnote
        ldx #C_LGR
        plp
        bne mlname
        ldx #C_ORA              ; the root
mlname  stx mlc
        inc gp                  ; (column 1)
        jsr notename            ; (changes cp)
        ldy #0
        lda (gp),y              ; upper case: E3, F#2
        ora #$40
        sta (gp),y
        lda mrw
        jsr rowptr
        ldy #3
        lda mlc
-       sta (cp),y
        dey
        bne -
        jmp mlnext
mldrum  lda mrw                 ; drums: the two sounds' names, coloured
        asl a
        asl a
        tax
        lda kitabbr,x
        ldy #1
        sta (gp),y
        lda kitabbr+1,x
        iny
        sta (gp),y
        lda kitabbr+2,x
        ldy #4
        sta (gp),y
        lda kitabbr+3,x
        iny
        sta (gp),y
        lda mrw
        asl a
        tax
        lda drcol,x
        ldy #1
        sta (cp),y
        iny
        sta (cp),y
        lda drcol+1,x
        ldy #4
        sta (cp),y
        iny
        sta (cp),y
mlnext  inc mrw
        lda mrw
        cmp #NROWS
        beq +
        jmp mrow1
+       jmp mnotes2

; the steps only (an edit): columns 7-38 anew, then the notes
ui_steps
        lda tweakon
        beq +
        jmp ui_tweak
+       lda #0
        jsr mgrid
mnotes2 ldx lane                ; the scroll arrows, column 38
        beq +
        lda #G_UP
        sta SCR_SCREEN + MROW*40 + 38
        lda #G_DOWN
        sta SCR_SCREEN + (MROW+NROWS-1)*40 + 38
        lda #C_LGR
        sta SCR_COLRAM + MROW*40 + 38
        sta SCR_COLRAM + (MROW+NROWS-1)*40 + 38
+       jsr mechoes
        jsr mnotes
        lda #$ff
        sta lstep2              ; the playhead's colours again
        sta cursat
        rts

; A = 0: columns 7-38 (the steps), else 1-38: the dots (brighter on the
; beats) and blanks; unrolled over the 7 rows (no colours for blanks)
mgrid   beq mg1
        ldx #5
        lda #$20
-       .for r = 0, r < NROWS, r += 1
        sta SCR_SCREEN + (MROW+r)*40 + 1,x
        .next
        dex
        bpl -
mg1     ldx #15
-       txa
        asl a
        tay
        lda #G_DOT
        .for r = 0, r < NROWS, r += 1
        sta SCR_SCREEN + (MROW+r)*40 + MCOL,y
        .next
        lda #$20
        .for r = 0, r < NROWS, r += 1
        sta SCR_SCREEN + (MROW+r)*40 + MCOL+1,y
        .next
        lda dotcol,x
        .for r = 0, r < NROWS, r += 1
        sta SCR_COLRAM + (MROW+r)*40 + MCOL,y
        .next
        dex
        bpl -
        rts
mlc     .byte 0

; the singer's echoes: where they land (on empty steps of the bar), grey
mechoes lda lane
        cmp #2
        bne me99
        lda esteps
        beq me99
        ldy #32+15-1            ; (the singer's row: 32-47)
me1     sty mstp
        lda (ep),y
        beq me8
        sta mval
        tya
        clc
        adc esteps
        cmp #48
        bcs me8
        tay
        lda (ep),y              ; a step that sings itself: no echo shown
        bne me8
        tya
        and #15
        sta mcnt
        lda mval
        jsr srowof
        cmp #NROWS
        bcs me8
        jsr rowptr
        lda mval
        jsr kindglyph
        pha
        lda mcnt
        asl a
        adc #MCOL
        tay
        pla
        sta (gp),y
        lda #C_GRY
        sta (cp),y
me8     ldy mstp
        dey
        cpy #32
        bcs me1
me99    rts

; the notes, steps 0-15 (a bass note's hold after it, so the next note
; draws over it)
mnotes  lda lane
        asl a
        asl a
        asl a
        asl a
        sta mbase
        lda #0
        sta mstp
mst1    lda mstp
        ora mbase
        tay
        lda (ep),y
        bne +
        jmp ms8
+       sta mval
        ldx lane
        bne ms2
        sec                     ; drums: row (role - 1) / 2, a block on the
        sbc #1                  ; left, a ball on the right
        cmp #14
        bcc +
        jmp ms8
+
        tax
        lsr a
        jsr rowptr
        lda drcol,x
        sta mcol
        txa
        lsr a
        lda #G_FULL
        bcc msput
        lda #G_BALL
        bne msput
ms2     dex
        bne ms3
        lda mval                ; bass: a note (orange; off the scale light
        jsr browof              ; red), one sliding in (a yellow arrow)
        cmp #NROWS
        bcs ms8
        jsr rowptr
        lda mval
        and #$1f
        tax
        lda #C_ORA
        ldy brow,x
        bpl +
        lda #C_LRD
+       sta mcol
        lda #G_FULL
        ldx mval
        bpl msput
        lda #C_YEL
        sta mcol
        lda #G_ARROW
        bne msput
ms3     lda mval                ; singer: the kind's mark
        jsr srowof
        cmp #NROWS
        bcs ms8
        jsr rowptr
        lda #C_LBL
        sta mcol
        lda mval
        jsr kindglyph
msput   pha
        lda mstp
        asl a
        adc #MCOL
        tay
        pla
        sta (gp),y
        lda mcol
        sta (cp),y
        lda lane                ; the bass: its hold, 2 * (length - 1)
        cmp #1
        bne ms8
        lda mval
        lsr a
        lsr a
        lsr a
        lsr a
        and #6
        beq ms8
        sta mcnt
-       iny
        cpy #38
        bcs ms8
        lda #G_SUST
        sta (gp),y
        lda #C_ORA
        sta (cp),y
        dec mcnt
        bne -
ms8     inc mstp
        lda mstp
        cmp #16
        beq +
        jmp mst1
+       rts

mbase   .byte 0
mstp    .byte 0
mval    .byte 0
mcnt    .byte 0
mcol    .byte 0

; A = matrix row 0-6: gp / cp on it (keeps X, Y)
rowptr  clc
        adc #MROW
        stx rpx
        tax
        lda rowlo,x
        sta gp
        sta cp
        lda rowhi,x
        sta gp+1
        clc
        adc #COLOFS
        sta cp+1
        ldx rpx
        rts
rpx     .byte 0

; A = a singer step byte -> its kind's mark (changes X)
kindglyph
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        tax
        lda kindg,x
        rts
kindg   .byte G_BALL, G_HEART, G_RING, $3f      ; mew, meow, ooh, mrr?

; the 14 drum sounds' names for row 23's hint, 8 characters each
        .enc "screen"
drname  .text "Kick    Boom    Snare   Bap     Clap    Rim     "
        .text "Hat     Open HatShaker  Ride    Ghost   Dust    "
        .text "Skank   Drop    "
        .enc "none"
        .cerror * - drname != 14 * 8, "drname: 14 names of 8"

dotcol  .byte [C_LGR, C_GRY, C_GRY, C_GRY] x 4
mtchr   .byte [$20] x 6, [G_DOT, $20] x 16
mtcol   .byte [C_GRY] x 6
        .for i = 0, i < 16, i += 1
        .byte (i % 4) ? C_GRY : C_LGR, C_GRY
        .next
drcol   .byte C_LRD, C_RED, C_YEL, C_ORA, C_LGN, C_GRN, C_CYN, C_LBL
        .byte C_LGR, C_WHT, C_GRY, C_BRN, C_PUR, C_BLU

; ------------------------------------------------------------------ tweaks
; Each cat's settings page (seq.asm tweaks), over the matrix: the open tab
; clicked again (or T) opens it, again (or T, or another tab) closes it.
; An item: a label, then < value >; a click on < or > steps it, a right
; click resets it, a click on the label selects it (the keys' item); a
; checkbox toggles. A change plays the cat only with [x] Preview (row 23,
; P; off at first). Keys: CRSR up/down the item, left/right (or Q / A) the
; value, RETURN play, SHIFT+RETURN reset, P Preview, T back.
;   Meows  a row per kind (15-18): its mark and name (a click plays it,
;          new meows get the kind), Bend, Vowel, Tone 0-16 (8 = as made,
;          shown -8..+8); row 20 Cat Size (Fat Cat .. Newborn)
;   Drums  Sidechain 0-8 (each kick ducks the bass), Tune 0-16 (8 = as made)
;   Bass   Level 0..-8; Delay (off, 1 2 3 4 6 8 12 steps; SID 2), Wave
;          (Style, Pulse, Saw, Tri); [ ] Meowize (the bass through the
;          meows' filter), [ ] Res boost (resonance up; with Meowize the
;          bass notes sweep the filter), [ ] Dub filter (the delay's
;          repeats through SID 2's filter, swept)
tweakon .byte 0
tsel    .byte 0                 ; the selected item (of the page's)

; an item: row, label column, value column (its "<"), format, the byte,
; how (0 the byte, 1 high nibble, 2 low nibble, 3 bit 0, 4 bit 1, 5 bit 2), max,
; default,
; the label (low byte of its text; all in tlabels' page)
TF_NUM   = 0
TF_DELAY = 1
TF_WAVE  = 2
TF_BOX   = 3
TF_LVL   = 4               ; a level: 0, -1 .. -8 (stored 0 .. 8)
TF_SIZE  = 5               ; the meows' Cat Size: Fat Cat .. Newborn (0-3)
titem   .macro row, lcol, vcol, fmt, var, how, max, def, lab
        .byte \row, \lcol, \vcol, \fmt, <\var, >\var, \how, \max, \def, <\lab
        .endm
TI_LEN  = 10
titems
ti_meow .for k = 0, k < 4, k += 1
        #titem 15+k, 8, 13, TF_NUM, twbend+k, 0, 16, 8, tl_bend
        #titem 15+k, 18, 24, TF_NUM, twvowel+k, 0, 16, 8, tl_vowel
        #titem 15+k, 29, 34, TF_NUM, twtone+k, 0, 16, 8, tl_tone
        .next
        #titem 20, 3, 12, TF_SIZE, tflags, 1, 3, 0, tl_csize
ti_drum #titem 16, 2, 13, TF_NUM, twside, 2, 8, 0, tl_side
        #titem 18, 2, 13, TF_NUM, twtune, 0, 16, 8, tl_tune
ti_bass #titem 15, 2, 13, TF_LVL, twside, 1, 8, 0, tl_level
        #titem 17, 2, 13, TF_DELAY, btweak, 1, 7, 0, tl_delay
        #titem 17, 25, 23, TF_BOX, tflags, 5, 1, 0, tl_dubf
        #titem 19, 2, 13, TF_WAVE, btweak, 2, 3, 0, tl_wave
        #titem 19, 25, 23, TF_BOX, tflags, 3, 1, 0, tl_meowz
        #titem 21, 25, 23, TF_BOX, tflags, 4, 1, 0, tl_resb
tifirst .byte (ti_drum - titems) / TI_LEN, (ti_bass - titems) / TI_LEN, 0
ticount .byte 2, 6, 13

        .align 256              ; (the labels share a page: tputs)
        .enc "uireg"
tlabels
tl_bend  .null "Bend"
tl_vowel .null "Vowel"
tl_tone  .null "Tone"
tl_side  .null "Sidechain"
tl_tune  .null "Tune"
tl_delay .null "Delay"
tl_wave  .null "Wave"
tl_meowz .null "Meowize"
tl_dubf  .null "Dub filter"
tl_level .null "Level"
tl_csize .null "Cat Size"
tl_resb  .null "Res boost"
tl_kick  .null "Each kick ducks the bass"
tl_sid2  .null "Delay: on SID 2"
        .enc "none"
        .cerror (>tlabels) != (>(*-1)), "the labels share a page"
        .enc "screen"
tdelay  .text "off  1  2  3  4  6  8 12"     ; 3 characters each
twaves  .text "StylePulse Saw  Tri "         ; 5
tsizes  .text "Fat Cat Tomcat KittenNewborn"   ; 7
tkname  .text "Mew MeowOoh Mrr?"
        .enc "none"
tvwidth .byte 2, 3, 5, 1, 2, 7               ; the value's width by format
tdelstp .byte 0, 1, 2, 3, 4, 6, 8, 12        ; (the delay's steps: seq.asm dsteps)

tweak_open
        lda #1
        sta tweakon
        lda #0
        sta tsel
        sta spick               ; (a settings page, not the style list)
        jmp tdirty
tweak_close
        lda #0
        sta tweakon
        sta spick
        jmp tdirty

; X = item (absolute): ti_ptr points at it; keeps X
tiptr   txa
        stx tix
        asl a                   ; * 10
        sta tmp
        asl a
        asl a
        clc
        adc tmp
        clc
        adc #<titems
        sta tip
        lda #>titems
        adc #0
        sta tip+1
        ldx tix
        rts
tix     .byte 0
tip     = $de                   ; 2 bytes of zero page: the item (free after the title)
tvar    .word 0

; the selected item's absolute index -> X
tselx   ldx lane
        lda tifirst,x
        clc
        adc tsel
        tax
        rts

; X = item: A = its value (0..max)
tval    jsr tiptr
        ldy #4
        lda (tip),y
        sta tva+1
        iny
        lda (tip),y
        sta tva+2
        iny
        lda (tip),y
        sta thow
tva     lda $ffff               ; (the byte: set above)
        ldy thow
        beq tv9
        dey
        bne +
        lsr a                   ; high nibble
        lsr a
        lsr a
        lsr a
        rts
+       dey
        bne +
        and #$0f                ; low nibble
        rts
+       dey
        bne +
        and #1                  ; bit 0
        rts
+       dey
        bne +
        lsr a                   ; bit 1
        and #1
        rts
+       lsr a                   ; bit 2
        lsr a
        and #1
tv9     rts
thow    .byte 0

; X = item, A = value: store it
tstore  sta tnew
        jsr tiptr
        ldy #4
        lda (tip),y
        sta tsa+1
        sta tsb+1
        iny
        lda (tip),y
        sta tsa+2
        sta tsb+2
        iny
        lda (tip),y
        tay
tsa     lda $ffff
        cpy #0
        bne +
        lda tnew                ; the byte
        jmp tsb
+       cpy #1
        bne +
        and #$0f                ; high nibble
        sta tmp
        lda tnew
        asl a
        asl a
        asl a
        asl a
        ora tmp
        jmp tsb
+       cpy #2
        bne +
        and #$f0                ; low nibble
        ora tnew
        jmp tsb
+       cpy #3
        bne +
        and #$fe                ; bit 0
        ora tnew
        jmp tsb
+       cpy #4
        bne +
        and #$fd                ; bit 1
        sta tmp
        lda tnew
        asl a
        ora tmp
        jmp tsb
+       and #$fb                ; bit 2
        sta tmp
        lda tnew
        asl a
        asl a
        ora tmp
tsb     sta $ffff
        lda tflags              ; (Meowize: the filter routing now)
        cmp twlastf
        beq +
        sta twlastf
        lda route1
        jsr wroute1
+       rts
tnew    .byte 0
twlastf .byte 0

; X = item, A = -1 / +1 / 0 (reset): change it, play the cat, redraw
tstep   sta tdir
        jsr tiptr               ; a level: < quieter (stored up), > louder
        ldy #3
        lda (tip),y
        cmp #TF_LVL             ; (and a Cat Size: < smaller)
        beq +
        cmp #TF_SIZE
        bne ++
+       lda #0
        sec
        sbc tdir
        sta tdir
+       jsr tval
        ldy tdir
        beq tsreset
        bmi tsdown
        ldy #7                  ; (max: the item's byte 7)
        pha
        jsr tiptr
        lda (tip),y
        sta tmax
        pla
        cmp tmax
        bcs tsdone
        adc #1
        bne tsput
tsdown  cmp #0
        beq tsdone
        sec
        sbc #1
        jmp tsput
tsreset jsr tiptr
        ldy #8
        lda (tip),y
tsput   jsr tstore
tsdone  jsr tauto
        jmp sdirty

; a change's audition: only with [x] Preview (RETURN and a meow's mark
; always play)
tauto   lda hear
        bne +
        rts
+       jmp tplay
heartog lda hear                ; P / a click: Preview on / off
        eor #1
        sta hear
        jmp setlane
tdir    .byte 0
tmax    .byte 0

; play the open cat: a kick, a bass note, or the selected meow's kind
tplay   lda lane
        bne +
        lda #1                  ; drums: BD
        jmp trig_drum
+       cmp #1
        bne +
        lda lastv+1             ; bass: the last note (or the root)
        and #$7f
        bne tpb
        lda #13
tpb     jsr trig_bass
        lda running
        bne tp9
        lda #12
        sta audt
tp9     rts
+       lda tsel                ; meows: the selected row's kind
        sta tmp
        lda #0
-       ldy tmp                 ; (tsel / 3)
        cpy #3
        bcc +
        sec
        lda tmp
        sbc #3
        sta tmp
        inc tkind
        bne -
+       lda tkind
        ldx #0
        stx tkind
        cmp #4                  ; (Level: a meow)
        bcc +
        lda #1
+
        ; fall through
; A = meow kind: play it (on the last meow's degree; new meows get it)
tplayk  asl a
        asl a
        asl a
        asl a
        asl a
        sta tmp
        lda lastv+2
        and #$1f
        bne +
        lda #6
+       ora tmp
        sta lastv+2
        ldx #0                  ; (no echoes)
        jmp trig_sing
tkind   .byte 0

; the page: rows 15-21
ui_tweak
        ldx #37                 ; blank (columns 1-38)
        lda #$20
-       .for r = 0, r < NROWS, r += 1
        sta SCR_SCREEN + (MROW+r)*40 + 1,x
        .next
        dex
        bpl -
        lda spick               ; the style list (slots.asm)
        beq +
        jsr pkdraw
        lda #$ff
        sta lstep2
        rts
+
        lda lane                ; meows: the marks and names
        cmp #2
        bne utw2
        lda #3
        sta mrw
-       lda mrw
        jsr rowptr
        ldx mrw
        ldy #1
        lda kindg,x
        sta (gp),y
        lda #C_LBL
        sta (cp),y
        txa
        asl a
        asl a
        tax
        ldy #3
-       lda tkname,x
        sta (gp),y
        lda #C_LGR
        sta (cp),y
        inx
        iny
        cpy #7
        bne -
        dec mrw
        bpl --
utw2    lda lane                ; drums: a hint
        bne +
        lda #6
        jsr rowptr
        ldx #<tl_kick
        ldy #13
        lda #C_GRY
        jsr tputs
+       lda lane                ; bass: the delay needs SID 2
        cmp #1
        bne +
        lda sid2+1
        bne +
        lda #6
        jsr rowptr
        ldx #<tl_sid2
        ldy #2
        lda #C_GRY
        jsr tputs
+       ldx lane                ; the items
        lda ticount,x
        sta tcnt
        lda tifirst,x
        tax
-       jsr tdraw
        inx
        dec tcnt
        bne -
        lda #$ff
        sta lstep2
        sta cursat
        rts
tcnt    .byte 0

; X (low byte) = a label in tlabels' page, Y = column, A = colour: on the
; row at gp / cp
tputs   sta tmp
        stx tps+1
        ldx #0
tps     lda tlabels,x           ; (the low byte set above)
        beq +
        sta (gp),y
        lda tmp
        sta (cp),y
        inx
        iny
        bne tps
+       rts

; X = item: its label, < value > (keeps X)
tdraw   stx tdx
        jsr tiptr
        ldy #0
        lda (tip),y             ; its row
        sec
        sbc #MROW
        jsr rowptr
        ldx tdx                 ; the label: white when selected
        jsr tselx2
        php
        lda #C_GRY
        plp
        bne +
        lda #C_WHT
+       sta tlc
        jsr tiptr
        ldy #9
        lda (tip),y
        sta tlab
        ldy #1
        lda (tip),y
        tay
        ldx tlab
        lda tlc
        jsr tputs
        ldx tdx
        jsr tiptr
        ldy #3
        lda (tip),y
        sta tfmt
        ldy #2
        lda (tip),y
        sta tvc
        ldx tdx
        jsr tval
        sta tv
        lda tfmt
        cmp #TF_BOX
        bne tdv
        ldy tvc                 ; a checkbox
        lda #G_BOXE
        ldx tv
        beq +
        lda #G_BOXX
+       sta (gp),y
        lda #C_WHT
        sta (cp),y
        ldx tdx
        rts
tdv     ldy tvc                 ; < value >
        lda #G_LT2
        sta (gp),y
        lda #C_LGR
        sta (cp),y
        iny
        lda tfmt
        cmp #TF_LVL
        bne +
        lda tv                  ; a level: 0, -1 .. -8
        beq tdzero
        pha
        lda #$2d
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        pla
        ora #$30
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        jmp tdgt
+       lda tfmt
        bne tdtext
        ldx tdx                 ; a number: as made shows 0, the rest +n / -n
        jsr tiptr               ; (when as made isn't 0: Bend, Vowel, Tone,
        sty tdy                 ; Tune)
        ldy #8
        lda (tip),y
        ldy tdy
        cmp #0
        beq tdplain
        sta tmp
        lda tv
        sec
        sbc tmp
        beq tdzero
        ldx #$2b                ; "+"
        bcs +
        eor #$ff
        adc #1                  ; (C clear: two's complement)
        ldx #$2d                ; "-"
+       pha
        txa
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        pla
        ora #$30
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        jmp tdgt
tdzero  lda #$20
        sta (gp),y
        iny
        lda #$30
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        jmp tdgt
tdplain lda tv                  ; a number, 2 digits
        ldx #$30
-       cmp #10
        bcc +
        sbc #10
        inx
        bne -
+       pha
        txa
        cpx #$30
        bne +
        lda #$20
+       sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        pla
        ora #$30
        sta (gp),y
        lda #C_WHT
        sta (cp),y
        iny
        jmp tdgt
tdtext  ldx tv                  ; a name: delay (3), wave (5)
        lda tfmt
        cmp #TF_DELAY
        bne +
        lda tdelofs,x
        tax
        lda #3
        sta tw
-       lda tdelay,x
        jsr tdput
        dec tw
        bne -
        jmp tdgt
+       cmp #TF_SIZE
        bne +
        lda tszofs,x
        tax
        lda #7
        sta tw
-       lda tsizes,x
        jsr tdput
        dec tw
        bne -
        jmp tdgt
+       lda twofs,x
        tax
        lda #5
        sta tw
-       lda twaves,x
        jsr tdput
        dec tw
        bne -
tdgt    lda #G_GT2
        sta (gp),y
        lda #C_LGR
        sta (cp),y
        ldx tdx
        rts
tdput   sta (gp),y
        lda #C_WHT
        sta (cp),y
        inx
        iny
        rts
tdelofs .byte 0, 3, 6, 9, 12, 15, 18, 21
twofs   .byte 0, 5, 10, 15
tszofs  .byte 0, 7, 14, 21
tdx     .byte 0
tdy     .byte 0
tlc     .byte 0
tlab    .byte 0
tfmt    .byte 0
tvc     .byte 0
tv      .byte 0
tw      .byte 0

; X = item: Z set when it is the selected one (keeps X)
tselx2  stx tselsv
        lda tselsv
        ldy lane
        sec
        sbc tifirst,y
        cmp tsel
        php
        ldx tselsv
        plp
        rts
tselsv     .byte 0

G_LT2   = $f3                   ; "<", ">" (thin chevrons)
G_GT2   = $eb
G_BOXE  = $e8                   ; a checkbox, empty / ticked
G_BOXX  = $dc

; a click on the page: Y = row, ccol, side
tclick  lda spick               ; the style list (slots.asm)
        beq +
        jmp pkclick
+       sty trow
        ldx lane                ; meows: a click on a mark or name plays it
        cpx #2
        bne tc1
        lda ccol
        cmp #7
        bcs tc1
        tya
        sec
        sbc #MROW
        cmp #4                  ; (rows 15-18; Level's below)
        bcs tc1
        jmp tplayk
tc1     ldx lane                ; the item on this row whose part is here
        lda ticount,x
        sta tcnt
        lda tifirst,x
        tax
tc2     jsr tiptr
        ldy #0
        lda (tip),y
        cmp trow
        beq +
        jmp tcnext
+       ldy #3                  ; a checkbox: its box or its label
        lda (tip),y
        cmp #TF_BOX
        bne +
        ldy #2
        lda (tip),y
        cmp ccol
        beq tcbox
        ldy #1
        lda (tip),y
        cmp ccol
        beq tcbox
        bcs tcnext
        clc
        adc #7
        cmp ccol
        bcc tcnext
tcbox   jsr tsetsel
        jsr tval
        eor #1
        jsr tstore
        jsr tauto
        jmp sdirty
+       ldy #2                  ; "<" at vcol, ">" at vcol + 1 + width
        lda (tip),y
        cmp ccol
        beq tcless
        sta tvc
        ldy #3
        lda (tip),y
        tay
        lda tvwidth,y
        sec
        adc tvc
        cmp ccol
        beq tcmore
        bcc tcnext              ; (past it)
        lda ccol                ; the label or the value: select (right
        ldy #1                  ; click on the value: reset)
        cmp (tip),y
        bcc tcnext
        jsr tsetsel
        lda ccol
        cmp tvc
        bcc +
        lda side
        beq +
        lda #0
        jmp tstep
+       jmp sdirty
tcless  jsr tsetsel
        lda #$ff
        ldy side
        beq +
        lda #0
+       jmp tstep
tcmore  jsr tsetsel
        lda #1
        ldy side
        beq +
        lda #0
+       jmp tstep
tcnext  inx
        dec tcnt
        beq tc9
        jmp tc2
tc9     rts
trow    .byte 0

; X = item (absolute): it becomes the selected one (keeps X)
tsetsel stx tselsv
        txa
        ldy lane
        sec
        sbc tifirst,y
        sta tsel
        ldx tselsv
        rts

; the keys on the page
keys_tweak
        #pressed K_T
        beq +
        jmp tweak_close
+       lda spick               ; the style list: only T (and 1-0, keys_play)
        beq +
        rts
+       #pressed K_P            ; P: Preview on / off
        beq +
        jmp heartog
+       #pressed K_CBM          ; C=: the next cat's page
        beq +
        jsr nexttab
        jmp tweak_open
+       #pressed K_CRSRUD       ; the item
        beq kt2
        ldx lane
        jsr shifted
        bne +
        ldy tsel
        iny
        tya
        cmp ticount,x
        bcc ++
        lda #0
        beq ++
+       ldy tsel
        dey
        tya
        bpl +
        lda ticount,x
        sec
        sbc #1
+       sta tsel
        jsr sdirty
kt2     #pressed K_CRSRLR       ; the value (and Q, A)
        beq kt3
        jsr shifted
        beq kt4
        lda #$ff
        bne kt5
kt3     #pressed K_Q
        beq +
kt4     lda #1
        bne kt5
+       #pressed K_A
        beq kt6
        lda #$ff
kt5     pha
        jsr tselx
        pla
        jmp tstep
kt6     #pressed K_RETURN
        beq +
        jsr shifted
        beq kt9
        jsr tselx
        lda #0
        jmp tstep
+       rts
kt9     jmp tplay

; ------------------------------------------------------------------ each frame
; the transport, the cats' names flashing, the playhead, the cursor
ui_tick lda running             ; the transport when it changed (rec blinks)
        cmp ltrans
        bne +
        lda tempo
        cmp ltrans+2
        bne +
        lda rec
        cmp ltrans+1
        bne +
        cmp #0
        beq ++
+       jsr transport
+
        lda #$ff                ; the playhead: while the bar edited plays
        ldx running
        beq +
        ldx bar
        ldy song+5,x
        cpy eslot
        bne +
        lda step
+       cmp lstep2
        beq ut9
        pha
        jsr curoff              ; (the cursor's cell as it is first)
        lda #$ff
        sta cursat
        ldx lstep2              ; the old one off: row 14, its dots
        bmi +
        txa
        asl a
        tay
        lda r14buf+MCOL,y
        sta SCR_SCREEN + HEADROW*40 + MCOL,y
        lda #C_LGR
        sta SCR_COLRAM + HEADROW*40 + MCOL,y
        lda dotcol,x
        jsr phcol
+       pla
        sta lstep2
        tax
        bmi ut9
        asl a
        tay
        lda #G_DOWN
        sta SCR_SCREEN + HEADROW*40 + MCOL,y
        lda #C_WHT
        sta SCR_COLRAM + HEADROW*40 + MCOL,y
        jsr phcol
ut9     lda tweakon             ; (no cursor on the tweaks page)
        bne +
        jmp cursor
+       rts

; the empty steps of column Y + MCOL in colour A
phcol   sta tmp
        tya
        clc
        adc #MCOL
        tay
        .for r = 0, r < NROWS, r += 1
        lda SCR_SCREEN + (MROW+r)*40,y
        cmp #G_DOT
        bne +
        lda tmp
        sta SCR_COLRAM + (MROW+r)*40,y
+
        .next
        rts

; the cursor: a box on an empty step, a blink on a full one
cursor  lda crow
        asl a
        asl a
        asl a
        asl a
        ora curx
        cmp cursat
        beq +
        pha
        jsr curoff
        pla
        sta cursat              ; the new place: remember its cell
        jsr curptr
        lda (gp),y
        sta curg
        lda (cp),y
        sta curc
+       jsr curptr
        lda frame
        and #8
        beq +
        lda curg
        sta (gp),y
        lda curc
        sta (cp),y
        rts
+       lda curg
        cmp #G_DOT
        bne +
        lda #G_BOX
        sta (gp),y
+       lda #C_WHT
        sta (cp),y
        rts

; the cursor's old cell back
curoff  ldx cursat
        cpx #$ff
        beq +
        txa
        lsr a
        lsr a
        lsr a
        lsr a
        jsr rowptr
        txa
        and #15
        asl a
        adc #MCOL
        tay
        lda curg
        sta (gp),y
        lda curc
        sta (cp),y
+       rts

; gp / cp, Y: the cursor's cell
curptr  lda crow
        jsr rowptr
        lda curx
        asl a
        adc #MCOL
        tay
        rts

cursat  .byte $ff           ; row * 16 + step of the cell saved ($ff: none)
curg    .byte 0
curc    .byte 0
lstep2  .byte $ff
r14buf  .fill 40

; ------------------------------------------------------------------ row 23
ui_settings
        lda msgt                ; a message up: leave it
        beq +
        rts
+       ldx #39
-       lda #$20
        sta SCR_SCREEN + SETROW*40,x
        lda #C_GRY
        sta SCR_COLRAM + SETROW*40,x
        dex
        bpl -
        lda pmode
        beq setlane
        lda #C_LGR              ; live play: its keys (red when recording)
        ldx rec
        beq +
        lda #C_LRD
+       ldx #<t_live
        ldy #>t_live
        jmp puts23

setlane lda tweakon
        beq +
        lda spick               ; the style list's title
        beq sl0
        ldx #<t_twp
        ldy #>t_tweak
        lda #C_GRY
        jmp puts23
sl0     ldx lane
        lda ttitle,x
        tax
        ldy #>t_tweak
        lda #C_GRY
        jsr puts23
        lda #G_BOXE             ; [ ] Preview: a setting's change heard
        ldx hear
        beq sl1
        lda #G_BOXX
sl1     sta SCR_SCREEN + SETROW*40 + 23
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40 + 23
        rts
hear    .byte 0                 ; (off: changes aren't auditioned)
+       ldx lane
        beq sdrums
        dex
        beq +
        jmp ssing
+       jmp sbass

sdrums  ldx #<t_drums
        ldy #>t_drums
        lda #C_GRY
        jsr puts23
        lda swing
        ldx #6
        ldy #6
        jsr slider
        lda crow                ; what the buttons put on the row: "LMB
        asl a                   ; Kick  RMB Boom", the names in their colours
        tax
        asl a
        asl a
        asl a
        tay                     ; Y = row * 16: the left name, + 8 the right
        lda drcol,x
        sta tmp
        lda drcol+1,x
        sta tmp2
        ldx #0
-       lda drname,y
        sta SCR_SCREEN + SETROW*40 + 19,x
        lda tmp
        sta SCR_COLRAM + SETROW*40 + 19,x
        lda drname+8,y
        sta SCR_SCREEN + SETROW*40 + 32,x
        lda tmp2
        sta SCR_COLRAM + SETROW*40 + 32,x
        iny
        inx
        cpx #8
        bne -
        rts

sbass   ldx #<t_bass
        ldy #>t_bass
        lda #C_GRY
        jsr puts23
        jsr minusplus
        lda btransp
        ldx #6
        jsr signed2
        lda lastv+1             ; the length new notes get
        lsr a
        lsr a
        lsr a
        lsr a
        lsr a
        and #3
        clc
        adc #$31
        sta SCR_SCREEN + SETROW*40 + 16
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40 + 16
        lda #G_ARROW
        sta SCR_SCREEN + SETROW*40 + 24
        lda #C_YEL
        sta SCR_COLRAM + SETROW*40 + 24
        ldx #<t_slide
        ldy #>t_slide
        jmp puts23

; "-" at 4 and "+" at 9 (bass), or at 17 and 22 (singer)
minusplus
        ldx #0
        lda lane
        cmp #2
        bne +
        ldx #13
+       lda #$2d
        sta SCR_SCREEN + SETROW*40 + 4,x
        lda #$2b
        sta SCR_SCREEN + SETROW*40 + 9,x
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40 + 4,x
        sta SCR_COLRAM + SETROW*40 + 9,x
        rts

ssing   ldx #<t_sing
        ldy #>t_sing
        lda #C_GRY
        jsr puts23
        jsr minusplus
        ldx #5                  ; the echo: its place in ECHOS
-       lda echos,x
        cmp esteps
        beq +
        dex
        bne -
+       txa
        ldx #5
        ldy #5
        jsr slider
        lda transp
        ldx #19
        jsr signed2
        ldx #<t_hnone           ; the harmony: off / 3rd / 5th, "--" in mono
        ldy #>t_hnone
        lda sid2+1
        beq +
        ldx harmony
        lda hname,x
        tax
        ldy #>t_hoff
+       lda #C_LBL
        jsr puts23
        ldx #3                  ; the kinds: the one new meows get white
-       lda kindg,x
        ldy kindx,x
        sta SCR_SCREEN + SETROW*40,y
        txa
        asl a
        asl a
        asl a
        asl a
        asl a
        eor lastv+2
        and #$60
        bne +
        lda #C_WHT
        bne ++
+       lda #C_GRY
+       sta SCR_COLRAM + SETROW*40,y
        dex
        bpl -
        rts
kindx   .byte 33, 35, 37, 39
hname   .byte <t_hoff, <t_hoff, <t_h3, <t_h3, <t_h5

; A = value, X = track cells, Y = column: a slider (the knob at value)
slider  sta tmp
        stx tmp2
        sty slcol
        lda #G_SL_L0
        ldx tmp
        beq +
        lda #G_SL_L1
+       jsr slput
        ldx #0
-       lda #G_SL_E
        cpx tmp
        bcs +
        lda #G_SL_F
+       jsr slput
        inx
        cpx tmp2
        bne -
        lda #G_SL_R
        jsr slput
        lda tmp
        cmp tmp2
        bcs +
        sec
        adc slcol               ; value + column + 1
        tay
        lda #G_SL_K
        sta SCR_SCREEN + SETROW*40,y
+       rts
slput   sta SCR_SCREEN + SETROW*40,y
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40,y
        iny
        rts
slcol   .byte 0

; A = -7..+7 at row 23, columns X, X+1: "0" or "+n" / "-n" (yellow)
signed2 cmp #0
        bne +
        lda #$30
        sta SCR_SCREEN + SETROW*40 + 1,x
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40 + 1,x
        rts
+       ldy #$2b
        ora #0
        bpl +
        eor #$ff
        clc
        adc #1
        ldy #$2d
+       ora #$30
        sta SCR_SCREEN + SETROW*40 + 1,x
        tya
        sta SCR_SCREEN + SETROW*40,x
        lda #C_YEL
        sta SCR_COLRAM + SETROW*40,x
        sta SCR_COLRAM + SETROW*40 + 1,x
        rts

; X/Y = text pieces: a column, screen codes to a 0, ... to a column $ff;
; A = colour: on row 23
puts23  stx gp
        sty gp+1
        sta tmp
        ldy #0
p23a    lda (gp),y
        cmp #$ff
        beq p23z
        tax
p23b    iny
        lda (gp),y
        beq +
        sta SCR_SCREEN + SETROW*40,x
        lda tmp
        sta SCR_COLRAM + SETROW*40,x
        inx
        bne p23b
+       iny
        bne p23a
p23z    rts

        .enc "uireg"
t_drums .byte 0
        .null "Swing"
        .byte 15
        .null "LMB"
        .byte 28
        .null "RMB"
        .byte $ff
t_bass  .byte 0
        .null "Key"
        .byte 12
        .null "Len"
        .byte 20
        .null "RMB"
        .byte $ff
t_sing  .byte 0
        .null "Echo"
        .byte 13
        .null "Key"
        .byte 25
        .null "Harm"
        .byte $ff
        .enc "none"
        .align 256              ; (the three in one page: ttitle)
        .enc "uireg"
t_tweak
t_twd   .byte 0
        .null "Drum tweaks"
        .byte 13
        .null "RMB reset"
        .byte 25
        .null "Preview"
        .byte 33
        .null "T back"
        .byte $ff
t_twb   .byte 0
        .null "Bass tweaks"
        .byte 13
        .null "RMB reset"
        .byte 25
        .null "Preview"
        .byte 33
        .null "T back"
        .byte $ff
t_twm   .byte 0
        .null "Meow tweaks"
        .byte 13
        .null "RMB reset"
        .byte 25
        .null "Preview"
        .byte 33
        .null "T back"
        .byte $ff
t_twp   .byte 0
        .null "Styles: new sounds, same bars"
        .byte 33
        .null "T back"
        .byte $ff
        .cerror (>t_tweak) != (>(*-1)), "the tweak titles share a page"
ttitle  .byte <t_twd, <t_twb, <t_twm
t_live  .byte 1
        .null "Live: pads  RETURN rec  DEL undo  <- back"
        .byte $ff
        .enc "screen"
t_slide .byte 25
        .null "Slide"
        .byte $ff
t_hoff  .byte 30
        .null "Off"
        .byte $ff
t_h3    .byte 30
        .null "3rd"
        .byte $ff
t_h5    .byte 30
        .null "5th"
        .byte $ff
t_hnone .byte 30
        .null "--"
        .byte $ff
        .enc "none"

; ------------------------------------------------------------------ row 24
; the style, the mode, the bars (the edited one cyan);
; then row 23 and the chain
status  ldx #39
-       lda #$20
        sta SCR_SCREEN + STROW*40,x
        lda #C_LGR
        sta SCR_COLRAM + STROW*40,x
        dex
        bpl -
        lda curslot             ; the slot's key (slots.asm): 1-9, 0
        clc
        adc #1
        cmp #10
        bcc +
        lda #0
+       ora #$30
        sta SCR_SCREEN + STROW*40 + 1
        lda sname               ; a slot with a name (loaded, saved): its
        beq stsname             ; first 9 characters
        ldy #0
-       cpy sname
        bcs +
        lda sname+1,y
        jsr pet2scr
        jmp ++
+       lda #$20
+       sta SCR_SCREEN + STROW*40 + 3,y
        lda #C_WHT
        sta SCR_COLRAM + STROW*40 + 3,y
        iny
        cpy #9
        bne -
        jmp stname9
stsname lda cstyle              ; else the style's name: 9 characters
        asl a
        sta tmp
        asl a
        asl a
        adc tmp
        tax
        ldy #0
-       lda stynames,x
        cpy #0                  ; the first letter upper case
        bne +
        cmp #27
        bcs +
        ora #$40
+       sta SCR_SCREEN + STROW*40 + 3,y
        lda #C_WHT
        sta SCR_COLRAM + STROW*40 + 3,y
        inx
        iny
        cpy #9 
        bne -
stname9 lda #C_WHT
        sta SCR_COLRAM + STROW*40
        sta SCR_COLRAM + STROW*40 + 1
        lda smode               ; the mode, yellow when not the style's own
        asl a
        clc
        adc smode
        tax
        ldy #0
-       lda modenames,x
        cpy #0
        bne +
        ora #$40
+       sta SCR_SCREEN + STROW*40 + 13,y
        lda #C_LGR
        cpx #3
        bcc +
        lda #C_YEL
+       sta SCR_COLRAM + STROW*40 + 13,y
        inx
        iny
        cpy #3
        bne -
        ldx #3                  ; the bars A-D (17-20)
-       txa
        clc
        adc #$41
        sta SCR_SCREEN + STROW*40 + 17,x
        lda #C_GRY
        cpx eslot
        bne +
        lda #C_CYN
+       sta SCR_COLRAM + STROW*40 + 17,x
        dex
        bpl -
        lda #$2d                ; the chain's - (red) and + (green)
        sta SCR_SCREEN + STROW*40 + 22
        lda #C_LRD
        sta SCR_COLRAM + STROW*40 + 22
        lda #$2b
        sta SCR_SCREEN + STROW*40 + 23
        lda #C_LGN
        sta SCR_COLRAM + STROW*40 + 23
        lda #$ff
        sta lbar
        lda #0
        sta msgt
        jsr ui_settings
        ; fall through

; the chain at columns 24-39 (up to 16 bars), the bar playing yellow
CHAINCOL = 24
songline
        ldx #15
-       lda #$20                ; past its end: blank
        cpx song+4
        bcs +
        lda song+5,x
        clc
        adc #$c1                ; "A".."D", regular
+       sta SCR_SCREEN + STROW*40 + CHAINCOL,x
        lda #C_LGR
        cpx bar
        bne +
        lda #C_YEL
+       sta SCR_COLRAM + STROW*40 + CHAINCOL,x
        dex
        bpl -
        rts

; X/Y = a 0-terminated screen-code message: on row 23 for 3 seconds
message stx gp
        sty gp+1
        ldx #39
-       lda #$20
        sta SCR_SCREEN + SETROW*40,x
        lda #C_WHT
        sta SCR_COLRAM + SETROW*40,x
        dex
        bpl -
        ldy #0
-       lda (gp),y
        beq +
        sta SCR_SCREEN + SETROW*40 + 1,y
        iny
        bne -
+       lda #150
        sta msgt
        rts

; ------------------------------------------------------------------ redraws
; once a frame: the tick, the message's timer, the chain when the bar
; changes, the matrix and rows 23-24 when dirty ($80: all; $40: the cursor
; moved: the drums' hint)
infos   lda helpon              ; (help up: nothing; the disk page: its
        beq +                   ; parts, diskui.asm)
        rts
+       lda diskon
        beq +
        jmp disk_tick
+       jsr ui_tick
        lda msgt
        beq +
        dec msgt
        bne +
        jsr ui_settings         ; the message is over
+       lda bar
        cmp lbar
        beq +
        sta lbar
        jsr stage_cycle         ; a new bar: the lights change colour
        jsr songline
+       lda dirty
        bne +
        rts
+       asl a
        bcc infst
        lda #40                 ; (~12000 cycles)
        jsr roomy               ; all: when the frame has room for it (else
        bcc inf9                ; the next frame), the matrix (the cursor's
        lda #0                  ; cell first), row 23, the chain
        sta dirty
        jsr curoff
        lda #$ff
        sta cursat
        jsr ui_matrix
        jsr ui_settings
        jsr songline
        jmp ui_tick
infst   asl a                   ; $20: an edit, the steps
        asl a
        bcc +
        lda #100                ; (~8000 cycles)
        jsr roomy
        bcc inf9
        lda #0
        sta dirty
        jsr curoff
        lda #$ff
        sta cursat
        jsr ui_steps
        jmp ui_settings
+       lda #0
        sta dirty
+       ldx lane                ; the cursor moved: the drums' hint
        bne inf9
        jmp ui_settings
inf9    rts

; A = a line: C set when this frame is still before it (or in the lower
; border), so a redraw fits: the main loop starts at line 250 and must be
; done by the next 250
roomy   sta rlim
        lda $d011
        bmi +                   ; lines 256-311
        lda $d012
        cmp #250
        bcs +                   ; 250-255
        cmp rlim
        bcs ++                  ; rlim-249: not now
+       sec
        rts
+       clc
        rts
rlim    .byte 0

; cursor moves: the hint only
cmoved  lda dirty
        ora #$40
        sta dirty
        rts
tdirty  jsr tabbar              ; the tab bar, then all the rest
sdirty  lda #$80
        sta dirty
        rts

rowlo   .byte <(SCR_SCREEN + range(25) * 40)
rowhi   .byte >(SCR_SCREEN + range(25) * 40)

; ------------------------------------------------------------------ help
; RUN/STOP: the keys over rows 12-24; any key or click closes it
HELPROW  = 12
help_open
        ldx #0
-       .for r = 0, r < 520, r += 130
        lda SCR_SCREEN + HELPROW*40 + r,x
        sta helpbuf + r,x
        lda SCR_COLRAM + HELPROW*40 + r,x
        sta helpbuf + 520 + r,x
        lda helptext + r,x
        sta SCR_SCREEN + HELPROW*40 + r,x
        .next
        inx
        cpx #130
        bne -
        ldx #12                 ; colours: the first 7 columns yellow, the
-       lda rowlo+HELPROW,x     ; rest light grey
        sta gp
        lda rowhi+HELPROW,x
        clc
        adc #COLOFS
        sta gp+1
        ldy #39
        lda #C_LGR
-       sta (gp),y
        dey
        cpy #8
        bcs -
        lda #C_YEL
        cpx #0                  ; (the frame's top and bottom: grey)
        beq +
        cpx #12
        bne ++
+       lda #C_LGR
+
-       sta (gp),y
        dey
        bne -
        lda #C_LGR
        sta (gp),y
        dex
        bpl ---
        lda #1
        sta helpon
        rts

helpkeys
        lda joyn
        bne help_close
        ldx #7
-       lda knew,x
        bne help_close
        dex
        bpl -
        rts
help_close
        ldx #0
-       .for r = 0, r < 520, r += 130
        lda helpbuf + r,x
        sta SCR_SCREEN + HELPROW*40 + r,x
        lda helpbuf + 520 + r,x
        sta SCR_COLRAM + HELPROW*40 + r,x
        .next
        inx
        cpx #130
        bne -
        lda #0
        sta helpon
        lda #1                  ; a fire that closed it is no tap
        sta fused
        lda #$ff
        sta lstep2
        sta cursat
        lda #$80
        sta dirty
        rts

helpbuf                         ; (the panel under the help or the disk page)
        .if WEB                 ; the web edition: the techno songs start
        .include "../gen/techno.inc"  ; here (slots.asm slots_techno
        .if (* - helpbuf) < 1040        ; unpacks them before the help or
        .fill 1040 - (* - helpbuf)      ; the disk page can use it)
        .endif
        .else
        .fill 1040
        .endif

; 13 rows of 40: a frame, "CatSynth 64 Help" on it; headings bold,
; the keys regular
helptext
        .byte $70, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $20, $43, $01, $14, $53, $19, $0e, $14, $08, $20, $36, $34, $20, $48, $05, $0c, $10, $20, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $6e
        .byte $5d, $20, $4d, $0f, $15, $13, $05, $20, $cc, $85, $86, $94, $af, $d2, $89, $87, $88, $94, $ba, $20, $81, $20, $83, $85, $8c, $8c, $a7, $93, $20, $94, $97, $8f, $20, $93, $8f, $95, $8e, $84, $93, $5d
        .byte $5d, $20, $4b, $05, $19, $13, $20, $20, $c3, $d2, $d3, $d2, $20, $8d, $8f, $96, $85, $20, $20, $d2, $c5, $d4, $d5, $d2, $ce, $af, $d3, $c8, $c9, $c6, $d4, $ab, $d2, $c5, $d4, $20, $cc, $af, $d2, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $c3, $bd, $20, $8e, $85, $98, $94, $20, $83, $81, $94, $20, $20, $d4, $20, $89, $94, $93, $20, $93, $85, $94, $94, $89, $8e, $87, $93, $20, $20, $20, $20, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $d1, $20, $c1, $20, $cb, $20, $c7, $20, $85, $84, $89, $94, $20, $20, $c4, $c5, $cc, $20, $83, $8c, $85, $81, $92, $20, $20, $d8, $20, $83, $8f, $90, $99, $5d
        .byte $5d, $20, $50, $0c, $01, $19, $20, $20, $d3, $d0, $c1, $c3, $c5, $20, $90, $8c, $81, $99, $20, $20, $ab, $20, $ad, $20, $94, $85, $8d, $90, $8f, $20, $20, $c5, $20, $85, $83, $88, $8f, $20, $20, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $b1, $ad, $b0, $20, $93, $8f, $8e, $87, $20, $20, $d3, $c8, $c9, $c6, $d4, $ab, $b1, $ad, $b0, $20, $89, $94, $93, $20, $93, $94, $99, $8c, $85, $20, $20, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $c6, $b1, $ad, $c6, $b7, $20, $82, $81, $92, $20, $20, $c3, $20, $83, $88, $81, $89, $8e, $20, $20, $cd, $20, $8d, $8f, $84, $85, $20, $20, $20, $20, $20, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $ac, $20, $ae, $20, $bc, $20, $be, $20, $8b, $85, $99, $20, $20, $c8, $20, $88, $81, $92, $8d, $8f, $8e, $99, $20, $20, $20, $20, $20, $20, $20, $20, $20, $5d
        .byte $5d, $20, $20, $20, $20, $20, $20, $20, $c3, $d4, $d2, $cc, $ab, $b1, $ad, $b3, $20, $8d, $95, $94, $85, $20, $20, $d3, $20, $cc, $20, $84, $89, $93, $8b, $20, $90, $81, $87, $85, $20, $20, $20, $5d
        .byte $5d, $20, $4c, $09, $16, $05, $20, $20, $bc, $ad, $20, $90, $81, $84, $93, $20, $20, $d2, $c5, $d4, $d5, $d2, $ce, $20, $92, $85, $83, $20, $20, $c4, $c5, $cc, $20, $95, $8e, $84, $8f, $20, $20, $5d
        .byte $5d, $20, $4a, $0f, $19, $20, $20, $20, $94, $88, $85, $20, $90, $8f, $89, $8e, $94, $85, $92, $20, $20, $86, $89, $92, $85, $20, $cc, $cd, $c2, $20, $20, $88, $85, $8c, $84, $20, $d2, $cd, $c2, $5d
        .byte $6d, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $20, $81, $8e, $99, $20, $8b, $85, $99, $20, $83, $8c, $8f, $93, $85, $93, $20, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $40, $7d

; the pointer: a white arrow, 10 x 14 (21 rows of 3 bytes, and a pad)
ptrspr  .byte $c0, 0, 0, $e0, 0, 0, $f0, 0, 0, $f8, 0, 0, $fc, 0, 0
        .byte $fe, 0, 0, $ff, 0, 0, $ff, $80, 0, $fc, 0, 0, $ee, 0, 0
        .byte $ce, 0, 0, $87, 0, 0, $07, 0, 0, $02, 0, 0
        .fill 64 - 42, 0

; our glyphs: a 5 1/4" floppy in 4 x 4 cells (rows of 4, codes G_FLOP),
; and the panel's one-cell disk icon (G_DISK)
G_FLOP  = [$67, $77, $68, $69, $6a, $74, $78, $79, $7f, $e0, $e3, $e6, $ed, $ee, $ef, $fd]
custgc  .byte G_FLOP, G_DISK
NCUSTG  = len(G_FLOP) + 1
custg
        .byte $ff,$ff,$f0,$f0,$f3,$f0,$f0,$f0
        .byte $ff,$ff,$00,$00,$ff,$00,$00,$00
        .byte $ff,$ff,$00,$00,$fc,$00,$00,$00
        .byte $ff,$ff,$0f,$0f,$0f,$0c,$0c,$0c
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$fc,$f0,$e0,$e1,$c2,$c4,$c4
        .byte $ff,$3f,$0f,$07,$87,$43,$23,$23
        .byte $fc,$ff,$ff,$ff,$ff,$3f,$3f,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $c2,$e1,$e0,$f0,$fc,$ff,$ff,$ff
        .byte $43,$87,$07,$0f,$3f,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $fc,$fc,$fc,$fc,$fc,$fc,$fc,$ff
        .byte $3f,$3f,$3f,$3f,$3f,$3f,$3f,$ff
        .byte $ff,$ff,$ff,$ff,$ff,$ff,$ff,$ff
        .byte $ff,$81,$ff,$e7,$db,$e7,$f7,$ff

uifont  .binary "../gen/uifont.bin"
