; ------------------------------------------------------------------ screen
; The CatSynth screen: the cat band on a stage (drum cat left behind its
; kit, bass cat middle with a bass and an amp, singer cat right at a mic),
; stage lights over them, a panel below with a row for each cat's step
; grid. The stage (rows 0-11) is a multicolour bitmap (art/stage_mc.py,
; tools/stagemc.py): its lights are colour RAM only (the lit pixels are
; the bitmap's %11), the rest of the screen is text (the split at row 12:
; ui.asm's raster interrupts, title.asm polls it). Text rows use the
; lowercase ROM font in codes $00-$7f and our glyphs in $80-$ff. The
; instruments and the moving parts (sticks, paws) are the 8 sprites, so a
; hit is a pointer and colour change: cheap, and on screen in the frame it
; is asked for. Data: build/screen.inc, build/stage.bin (tools/screen.py,
; art/band.py, art/stage_mc.py).
;
; Memory (VIC bank 3, $c000-$ffff: no character ROM image there, and a
; program from $0801 can grow to $bfff without meeting it):
;   $c000-$c3e7  screen (SCR_SCREEN)
;   $c3f8-$c3ff  sprite pointers
;   $c400-$c7bf  sprite blocks $10-$1e (SCR_NBLOCKS = 15), copied at init
;   $c7c0-$c7ff  free: block $1f
;   $c800-$cbff  charset $00-$7f: the lowercase ROM font, copied at init,
;                then our font over $00-$3f and $41-$5a (art/font.py)
;   $cc00-$cfff  charset $80-$ff: the stage front, the CH_* glyphs (rows
;                12 on, the title's)
;   $d800-$dbe7  colour RAM
;   $e000-$eeff  the stage, rows 0-11: a multicolour bitmap (build/stage.bin,
;                the program file's last part, copied here at start:
;                catsynth.asm stage_data);
;                its colours in the screen's rows 0-11 and their colour RAM
;   rows 0-11: $d011 = $3b, $d016 = $18, $d018 = $08 (bitmap $e000);
;   the rest: text, $d011 = $1b, $d016 = $08 (the split: ui.asm, title.asm)
;   $dd00 = %xxxxxx00, $0288 = $c0
;   all 8 sprites: $d000-$d010, $d015, $d017, $d01b-$d01d, $d025-$d02e
;
; Zero page: $f0-$f6, scratch only, inside screen_init and screen_frame
; (nothing is kept there between calls). The KERNAL IRQ's keyboard scan
; writes $f5/$f6: don't let it interrupt screen_frame (run your own IRQ,
; or call screen_frame from it).
;
; API
;   screen_init   blank, set VIC bank/charset/screen and the sprites, draw
;                 the stage, the panel and the band idle, lights idle;
;                 screen on. Changes $01 only for a moment, with interrupts
;                 off.
;   cat_pose      X = cat, A = pose (< SCR_NPOSE = 5, others are ignored);
;                 only records it.
;                 Keeps A, X, Y. Safe to call from an IRQ.
;                   cat 0 drums   0 idle: sticks up
;                                 1 snare: left stick down on it, it flashes
;                                 2 closed hi-hat: right stick on it, it
;                                   flashes white
;                                 3 open hi-hat / cymbal: right stick on
;                                   it, its top cymbal lifts and tilts,
;                                   white
;                                 4 kick: sticks up, the kick's head
;                                   flashes yellow
;                   cat 1 bass    0 idle, 1 pluck (paw through the strings,
;                                 strings shown ringing), 2 pluck with the
;                                 fretting paw moved down the neck
;                                 (3, 4: as 0)
;                   cat 2 singer  0 idle at the mic, 1 singing (mouth open),
;                                 2 ear flick (mouth shut, one ear tip a
;                                 little out: for echoes) (3, 4: as 0)
;                 Hold a pose a few frames, then 0. Bass: alternate 1 and
;                 2 on successive plucks (1 then 1 shows no new pluck).
;   stage_cycle   the lights move on to the next colour palette (each bar)
;   stage_hit     X = cat: its stage light (lamp, beam, pool on the boards)
;                 flashes and fades back over 16 frames through the cat's
;                 colour ramp (drums warm, bass green, singer pink). A hit
;                 while fading starts it again. Keeps A, X, Y. Safe to call
;                 from an IRQ.
;   screen_frame  once a frame: all 8 sprites from the poses (~330 cycles),
;                 the fading lights (~190 each, while one fades), then at
;                 most one cat whose frame changed (round robin; only the
;                 singer's do, 4 bitmap cells, ~550). Worst case
;                 measured by screentest: see the status row there.
;                 Changes A, X, Y.
;
;   screen_novu   a byte: set bit 7 while something else covers the panel
;                 (the title, a help overlay), or the VU meters' colour RAM
;                 writes (rows 17, 19, 21, columns 5-9) land on it; clear it
;                 when the panel is back. screen_init clears it.
;   screen_step   A = the step playing (0-15, $ff none): lights its cell on
;                 the ruler yellow and the beat LED red on steps 0/4/8/12.
;                 Call it when the step changes. Changes A, X. ~50 cycles.
;
; Look: $d021 = SCR_WALL_BG (dark grey) is the ground of the backdrop and
; the panel: a brick wall over the band (rows 1-4, lit by the beams), a
; plain backcloth behind it (rows 5-9), red curtains at the sides.
;
; Layout (build/screen.inc, from tools/screen.py)
;   row 0         the lighting truss, "catsynth 64" on it
;   rows 1-2      the lamps (lens on row 2), beams on rows 3-4
;   rows 5-9      the cats, 8x5 cells at columns 3, 16, 29 (SCR_CAT_COL_*);
;                 PA speakers at columns 0-1, 38-39, the bass amp at 25-27
;   rows 10-11    stage boards (FLOOR_ROW), 12 the stage front, 13 names
;   rows 14-22    the panel: a rounded bezel (PANEL_TOP, PANEL_BOT),
;                 columns 1-38
;   RULER_ROW 15  beat numbers 1-4 over steps 0/4/8/12, ticks between,
;                 the beat LED at column 29 (screen_step)
;   GRID_ROW_DRUM = 16, GRID_ROW_BASS = 18, GRID_ROW_SING = 20: the step
;                 grids, GRID_LEN = 16 cells from GRID_COL = 12 (columns
;                 12-27), blank. Columns 2-3: the instrument icon, 4-9 the
;                 name; the row under it, columns 4-8: the cat's VU meter
;                 (lit by its stage light, nothing to call). Columns 29-37
;                 of the grid rows are free.
;   SONG_ROW 23, STATUS_ROW 24: rounded end caps at columns 0 and 39; the
;                 main program's text goes in columns 1-38 (STRIP_COL0/1).
;   Cell N of a grid: SCR_SCREEN + GRID_ROW_x*40 + GRID_COL + N, and its
;   colour at SCR_COLRAM + the same offset (or the scr_grid* tables below).
;   Step glyphs (the sequencer picks one per cell, then its colour: the
;   cat's for a step that plays, GRID_DIM for an empty one, yellow for the
;   playhead):
;     CH_STEP_OFF        an empty step: a dot
;     CH_STEP_OFF_BEAT   an empty step on 0/4/8/12: a dot over a bar
;     CH_STEP_RING       the playhead on an empty step: a ring
;     CH_STEP_ON         a generic step: a ball
;     CH_DR_KICK, CH_DR_SNARE, CH_DR_HAT, CH_DR_CYM      drums
;     CH_BS_1 .. CH_BS_4 (a note, its tail as long as it lasts), CH_BS_SLIDE
;     CH_SG_MEW, CH_SG_MEOW, CH_SG_OOH, CH_SG_MRR       the meow kinds
;   Panel bits: CH_TICK, CH_LED, CH_VU, CH_BZ_* (bezel corners and edges);
;   any ROM letter $00-$7f. Codes $f0-$ff are the title's.

SCR_SCREEN  = $c000
SCR_CHARSET = $c800
SCR_COLRAM  = $d800
SCR_BITMAP  = $e000
D018_TOP    = $08               ; screen $c000, the bitmap $e000 (rows 0-11)
D018_TEXT   = $02               ; screen $c000, charset $c800 (the title's rows 12 on)

scr_fp  = $f0                   ; frame data / RLE source
scr_sp  = $f2                   ; screen / RLE destination
scr_cp  = $f4                   ; a cell's screen byte, then colour RAM (scr_cat)
scr_n   = $f6

screen_init
        lda #$2b                ; blank while it is drawn (bitmap: the top's mode)
        sta $d011
        lda #0
        sta $d015
        lda $dd02               ; bank select bits are outputs
        ora #3
        sta $dd02
        lda $dd00
        and #$fc                ; %00: bank 3
        sta $dd00
        lda #D018_TOP
        sta $d018               ; screen (bits 4-7), the bitmap (bit 3) in the bank
        lda #$18
        sta $d016               ; 40 columns, multicolour, no fine scroll
        lda #SCR_WALL_BG
        sta $d020
        sta $d021
        lda #>SCR_SCREEN        ; the KERNAL editor's screen, should it print
        sta $0288

        php                     ; the ROM font: character ROM in place of I/O,
        sei                     ; so no IRQ may run meanwhile
        lda $01
        pha
        and #$fb                ; CHAREN (bit 2) 0: the ROM at $d000-$dfff
        sta $01
        ldx #0
-       .for o = 0, o < $400, o += $100
        lda $d800+o,x           ; the lowercase set's first half
        sta SCR_CHARSET+o,x
        .next
        inx
        bne -
        pla
        sta $01
        plp
        ldx #0                  ; our font over it (art/font.py): $00-$3f,
-       lda scr_font,x          ; then the capitals $41-$5a
        sta SCR_CHARSET,x
        lda scr_font+$100,x
        sta SCR_CHARSET+$100,x
        cpx #26*8               ; (26 capitals, 8 bytes each)
        bcs +
        lda scr_fontuc,x
        sta SCR_CHARSET+$41*8,x
+       inx
        bne -
        ldx #0                  ; our codes from $80 (whole pages: a few
-       .for o = 0, o < SCR_NCHARS*8, o += $100   ; bytes past the end land
        lda scr_chars+o,x       ; in codes nothing shows)
        sta SCR_CHARSET+$400+o,x
        .next
        inx
        bne -
SCR_SPRLEN = SCR_NBLOCKS * 64   ; the sprites: exactly, the rest stays free
        .if SCR_SPRLEN >= $100
        ldx #0
-       .for o = 0, o < (SCR_SPRLEN & $ff00), o += $100
        lda scr_sprdata+o,x
        sta SCR_SPRITES+o,x
        .next
        inx
        bne -
        .fi
        .if (SCR_SPRLEN & $ff) != 0
        ldx #(SCR_SPRLEN & $ff) - 1
-       lda scr_sprdata+(SCR_SPRLEN & $ff00),x
        sta SCR_SPRITES+(SCR_SPRLEN & $ff00),x
        dex
        cpx #$ff                ; (down to 0, inclusive)
        bne -
        .fi

        lda #<scr_rscreen       ; the stage and panel: codes, then colours
        ldx #>scr_rscreen
        ldy #>SCR_SCREEN
        jsr scr_unrle
        lda #<scr_rcolour
        ldx #>scr_rcolour
        ldy #>SCR_COLRAM
        jsr scr_unrle

        ldx #2                  ; the cats idle (the bitmap's cells as at
-       lda #0                  ; load: the title may have left a pose), lights off
        sta scr_req,x
        sta scr_light,x
        ldy scr_snp,x           ; (cat*SCR_NPOSE: pose 0's frame)
        lda scr_cfr,y
        jsr scr_cat
        dex
        bpl -
        stx scr_rr              ; ($ff: cat 0 is looked at first)
        stx scr_lstep           ; (no step lit: the map has the ruler's colours)
        inx
        stx screen_novu         ; (0: the VU meters on)

        ldx #15                 ; sprite places, modes, shared colours
-       lda scr_sxy,x
        sta $d000,x
        dex
        bpl -
        lda #SCR_SXHI
        sta $d010               ; X bit 8 of each
        lda #SCR_SMC
        sta $d01c               ; multicolour
        lda #SCR_SXEXP
        sta $d01d               ; double width
        lda #0
        sta $d017               ; no double height
        sta $d01b               ; in front of the characters
        lda #SCR_MC0
        sta $d025               ; the shared colours 0, 1
        lda #SCR_MC1
        sta $d026
        jsr scr_spr
        lda #$ff
        sta $d015               ; all 8 on
        rts                     ; (still blank: the split's bottom half turns it
                                ; on, ui.asm irq_bottom / title.asm, with the
                                ; top's mode, $d011 = $3b)

; X = cat, A = pose: the request; screen_frame shows it
cat_pose
        cmp #SCR_NPOSE          ; out of range: ignored (it would index past
        bcs +                   ; the tables and draw garbage)
        sta scr_req,x
+       rts

; X = cat: its light flashes and fades
SCR_LIGHT = 16                  ; frames; ramp index = frames left / 2
stage_hit
        pha
        lda #SCR_LIGHT
        sta scr_light,x
        pla
        rts

; the lights' colour cycle: every cat on to the next palette (call it on
; each new bar). Keeps A, X, Y.
stage_cycle
        pha
        txa
        pha
        ldx scr_phase
        inx
        cpx #SCR_NPAL
        bcc +
        ldx #0
+       stx scr_phase
        .for c = 0, c < 3, c += 1   ; cat c: palette phase + c (wrapped), * 8
        txa
        .if c > 0
        clc
        adc #c
        cmp #SCR_NPAL
        bcc +
        sbc #SCR_NPAL
+
        .endif
        asl a
        asl a
        asl a
        sta scr_pal+c
        .next
        pla
        tax
        pla
        rts

; A = the step playing (0-15), $ff: none. Its ruler cell lights yellow, the
; beat LED red on steps 0, 4, 8, 12. Call it when the step changes (~50
; cycles). Changes A, X.
screen_step
        ldx scr_lstep           ; the last one back to the ruler's colour
        bmi +
        pha
        lda scr_rulc,x
        sta SCR_COLRAM+RULER_ROW*40+GRID_COL,x
        pla
+       sta scr_lstep
        tax
        bmi scrled              ; (none: the LED off)
        lda #7                  ; yellow
        sta SCR_COLRAM+RULER_ROW*40+GRID_COL,x
        txa
        and #3
        bne scrled
        lda #2                  ; a beat: red
        .byte $2c
scrled  lda #0                  ; off: black
        sta SCR_COLRAM+SCR_BEAT_LED
        rts

; once a frame (see the API above): sprites, fading lights, a cat redrawn
screen_frame
        jsr scr_spr
        .for c = 0, c < 3, c += 1   ; a fading light: a step down its ramp
        lda scr_light+c         ; (in the cat's palette of the moment)
        beq +
        dec scr_light+c
        lda scr_light+c
        lsr a
        tax                     ; X = level (the meters)
        ora scr_pal+c           ; Y = palette * 8 + level
        tay
        jsr [scr_lit0, scr_lit1, scr_lit2][c]   ; its colour RAM (screen.inc)
+
        .next
        lda #3                  ; then the characters: the cat after the
        sta scr_n               ; last one drawn first
        ldx scr_rr
-       inx
        cpx #3
        bcc +
        ldx #0
+       lda scr_req,x           ; its pose's character frame
        clc
        adc scr_snp,x           ; (cat*SCR_NPOSE)
        tay
        lda scr_cfr,y
        cmp scr_shown,x
        bne +                   ; changed: draw it
        dec scr_n
        bne -
        rts                     ; (all three as shown)
+       stx scr_rr
        ; fall through

; draw cat X's frame A: the bitmap cells its frames change (8 bitmap
; bytes, the screen byte, colour RAM each; ~130 cycles a cell); keeps X
scr_cat sta scr_shown,x
        tay
        lda scr_frlo,y
        sta scr_fp
        lda scr_frhi,y
        sta scr_fp+1
        lda scr_ncell,x
        beq scrc9
        sta scr_n
        lda scr_cell0,x
        sta scr_k
scrcell ldy scr_k
        lda scr_cbl,y           ; the cell in the bitmap
        sta scr_sp
        lda scr_cbh,y
        sta scr_sp+1
        lda scr_csl,y           ; its screen byte
        sta scr_cp
        lda scr_csh,y
        sta scr_cp+1
        ldy #7
-       lda (scr_fp),y
        sta (scr_sp),y
        dey
        bpl -
        ldy #8
        lda (scr_fp),y
        ldy #0
        sta (scr_cp),y
        lda scr_cp+1            ; colour RAM: the same offset
        clc
        adc #>(SCR_COLRAM - SCR_SCREEN)
        sta scr_cp+1
        ldy #9
        lda (scr_fp),y
        ldy #0
        sta (scr_cp),y
        lda scr_fp
        clc
        adc #10
        sta scr_fp
        bcc +
        inc scr_fp+1
+       inc scr_k
        dec scr_n
        bne scrcell
scrc9   rts
scr_k   .byte 0

; every sprite: the block and colour of its cat's pose (about 330 cycles)
scr_spr ldx #7
-       ldy scr_sown,x          ; (the cat it belongs to)
        lda scr_req,y
        clc
        adc scr_snp,x           ; sprite*SCR_NPOSE + pose
        tay
        lda scr_sptr,y
        sta SCR_SCREEN+$3f8,x   ; its pointer (block number)
        lda scr_scol,y
        sta $d027,x             ; its colour
        dex
        bpl -
        rts

; unpack RLE (count, value pairs; count 0 ends) from A/X to page Y
scr_unrle
        sta scr_fp
        stx scr_fp+1
        sty scr_sp+1
        ldy #0
        sty scr_sp
scrrun  lda (scr_fp),y          ; (Y = 0 here)
        beq scrrts
        tax
        iny
        lda (scr_fp),y
        dey
-       sta (scr_sp),y
        inc scr_sp
        bne +
        inc scr_sp+1
+       dex
        bne -
        lda scr_fp
        clc
        adc #2
        sta scr_fp
        bcc scrrun
        inc scr_fp+1
        bne scrrun              ; (always)
scrrts  rts

; a grid's first cell, drum/bass/singer: screen and colour RAM
SCR_GRID = [GRID_ROW_DRUM, GRID_ROW_BASS, GRID_ROW_SING] * 40 + GRID_COL
scr_gridlo  .byte <(SCR_SCREEN + SCR_GRID)
scr_gridhi  .byte >(SCR_SCREEN + SCR_GRID)
scr_cgridlo .byte <(SCR_COLRAM + SCR_GRID)
scr_cgridhi .byte >(SCR_COLRAM + SCR_GRID)

scr_req   .byte 0, 0, 0         ; the pose asked for
scr_shown .byte 0, 0, 0         ; the character frame on screen
scr_rr    .byte 0               ; the cat drawn last
scr_light .byte 0, 0, 0         ; frames of light left
scr_pal   .byte 0, 8, 16        ; each cat's palette * 8 (stage_cycle)
scr_phase .byte 0
scr_lstep .byte $ff             ; the step lit on the ruler
screen_novu .byte 0             ; bit 7: the VU meters are not drawn

        .include "../gen/screen.inc"
        .cerror SCR_NBLOCKS > 16, "sprites overflow $c400-$c7ff"
