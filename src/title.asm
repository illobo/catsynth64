; ------------------------------------------------------------------ title
; The CatSynth title (tools/title.py, build/title.inc): the band on its
; stage, where the main screen has it (rows 0-13), so title_tick drives it
; with cat_pose and stage_hit as in the main loop; below it two pages that
; take turns, wiped in a row a frame:
;   page 0  "CATSYNTH 64" in quad blocks over raster bars (catsim64's title
;           way: polled, cycle-exact, interrupts off), the credit
;   page 1  the keys
; and a 1-pixel scroller on row 24 (the prompt first): $d016 fine scroll
; and 38 columns set on line 242 and put back on line 251, polled.
;
; API
;   title_run     calls screen_init, draws the title, then once a frame:
;                 the bars, wait for line $fa, jsr title_tick (yours: the
;                 sequencer and the sound, up to ~2000 cycles; do NOT call
;                 screen_frame in it, title_run does), screen_frame, its
;                 own work. Returns when fire (port 2), SPACE or RETURN has
;                 been pressed and released (a key already held on entry
;                 must be released first), with the screen blanked
;                 ($d011 = $0b, sprites still on) and $dc00 = $ff: call
;                 screen_init next (it turns the VU meters back on: the
;                 title sets screen_novu). Changes A, X, Y; interrupts must
;                 be off.
;   title_quit    title_tick may set it non-zero to end the title as a key
;                 would (e.g. a timeout into a demo); title_run clears it.
;   title_endline the raster line (low byte) where the last frame's work
;                 ended, worst so far; the bars start at line T_BAR_TOP-4
;                 = 164, so it must stay below that (titletest shows it).
;
; Frame: lines 164-234 the bars (the CPU is busy: ~4500 cycles), line 250
; title_tick, screen_frame (~2000), then the next frame's bars built
; (~1400), a page row copied while a wipe runs (~1100), the prompt colour
; (~370), the keys (~70). With a 2000-cycle title_tick it ends near line
; 60 (measured: see titletest).
;
; Memory: code and data ~3 KB wherever it is placed (tbars and tbuf share
; a page: up to 255 bytes of padding). Charset codes $f0-$ff (quad blocks,
; $cf80-$cfff), screen rows 14-24 and their colour RAM: screen_init
; redraws all of it. Zero page $f0-$fc while title_run runs.

T_PAGE0   = 450                 ; frames each page shows (PAL: 9 s, 6 s)
T_PAGE1   = 300
t_src   = $f0                   ; page row copy: codes, colours, to screen,
t_srck  = $f2                   ; to colour RAM
t_dst   = $f4
t_dstk  = $f6
t_cnt    = $f8                   ; bar lines to go (tbars)
t_tmp     = $f9                   ; (tbars: bit t_tmp, 3 cycles)
t_sx    = $fa                   ; the scroller's fine scroll, 7-0
t_tp    = $fb                   ; 2 bytes: its next character

title_run
        jsr screen_init
        lda #$80                ; no VU meters: rows 14-23 are the title's
        sta screen_novu
        lda #$0b                ; blank while the title goes on
        sta $d011
        lda #$ff                ; keyboard: columns out, rows in
        sta $dc02
        lda #0
        sta $dc03
        ldx #16*8-1             ; the quad blocks
-       lda tquads,x
        sta SCR_CHARSET+T_QUAD0*8,x
        dex
        bpl -
        ldx #39                 ; the scroller's first 40 characters: the prompt
-       lda tscrolltext,x
        sta SCR_SCREEN+T_PROMPT_ROW*40,x
        dex
        bpl -
        lda #<(tscrolltext+40)
        sta t_tp
        lda #>(tscrolltext+40)
        sta t_tp+1
        lda #7
        sta t_sx
        lda #0
        sta tpage
        sta tstate
        sta tframe
        sta title_endline
        sta title_quit
        ldy #T_PAGE_ROWS-1      ; page 0 at once
-       jsr tcopy
        dey
        bpl -
        lda #T_PAGE_ROWS        ; no wipe running
        sta twrow
        lda #<T_PAGE0
        sta ttime
        lda #>T_PAGE0
        sta ttime+1
        jsr tbuild
        lda #$1b
        sta $d011

tloop   lda #T_BAR_END-T_BAR_TOP+1-T_NBAD   ; the lines without the bad ones
        sta t_cnt
        jsr tbars
        ldx #T_SPLIT            ; the scroller's row: its fine scroll, 38
-       cpx $d012               ; columns, set in the right border of the
        bne -                   ; line before (no sprites, not a bad line)
        ldy #6                  ; 43 cycles: the write lands at 51-58
        jsr tdly
        lda t_sx
        sta $d016
        ldx #T_SPLIT+9          ; and back under it, in the lower border
-       cpx $d012
        bne -
        lda #$08
        sta $d016
        jsr title_tick          ; (one line after $fa, as the main loop)
        jsr screen_frame
        inc tframe
        jsr tbuild              ; the next frame's bars
        jsr tpages
        jsr tscroll
        jsr tkeys
        lda title_quit          ; (title_tick may end it too)
        beq +
        sec                     ; C = 1: done (tkeys' C, or this)
+       php                     ; (C kept over the line check)
        lda $d012               ; how far the work got (bars at 164)
        cmp title_endline
        bcc +
        sta title_endline
+       plp
        bcc tloop
        lda #$0b                ; done: blank, the main screen next
        sta $d011
        lda #$08
        sta $d016
        lda #SCR_WALL_BG
        sta $d020
        sta $d021
        rts

; fire (port 2), SPACE, RETURN: C = 1 once one was pressed and all are up
tkeys   ldx #0
        lda #$7f                ; SPACE: column 7, row 4
        sta $dc00
        lda $dc01
        and #$10
        bne +
        inx
+       lda #$fe                ; RETURN: column 0, row 1
        sta $dc00
        lda $dc01
        and #$02
        bne +
        inx
+       lda #$ff                ; no column: $dc00 reads joystick 2
        sta $dc00
        lda $dc00
        and #$10
        bne +
        inx
+       lda tstate              ; 0: wait for all up, 1: for a press,
        beq tk0                 ; 2: for all up again
        cmp #1
        beq tk1
        cpx #0
        bne tkno
        sec
        rts
tk0     cpx #0
        bne tkno
        inc tstate
tkno    clc
        rts
tk1     cpx #0
        beq tkno
        inc tstate
        clc
        rts

; the pages: when a page's time is up the other one is wiped in, a row a
; frame from the top
tpages  ldy twrow
        cpy #T_PAGE_ROWS
        bcs +
        jsr tcopy
        inc twrow
        rts
+       lda ttime               ; ttime - 1 (16 bits)
        bne +
        dec ttime+1
+       dec ttime
        lda ttime
        ora ttime+1
        bne +
        lda tpage               ; time up: the other page, its time, the wipe
        eor #1
        sta tpage
        tax
        lda tptimelo,x
        sta ttime
        lda tptimehi,x
        sta ttime+1
        lda #0
        sta twrow
+       rts
tptimelo .byte <T_PAGE0, <T_PAGE1
tptimehi .byte >T_PAGE0, >T_PAGE1

; copy row Y (0-9) of page tpage to the screen; keeps Y
tcopy   sty t_tmp
        lda tpage               ; X = the row's index in the source tables
        beq +                   ; (page 1's rows after page 0's)
        tya
        clc
        adc #T_PAGE_ROWS
        tax
        .byte $2c               ; (bit abs: skip the ldx)
+       ldx t_tmp
        lda tsrclo,x
        sta t_src
        lda tsrchi,x
        sta t_src+1
        lda tsrcklo,x
        sta t_srck
        lda tsrckhi,x
        sta t_srck+1
        lda tdstlo,y
        sta t_dst
        sta t_dstk
        lda tdsthi,y
        sta t_dst+1
        clc                     ; its colour RAM: $1800 up, the same low byte
        adc #>(SCR_COLRAM-SCR_SCREEN)
        sta t_dstk+1
        ldy #39
-       lda (t_src),y
        sta (t_dst),y
        lda (t_srck),y
        sta (t_dstk),y
        dey
        bpl -
        ldy t_tmp
        rts

; each page row's address, indexed by row: the codes and colours of page 0
; then page 1 (tpage*.., title.inc), and its place on the screen
TROWS    = range(T_PAGE_ROWS) * 40   ; (a list: 0, 40, 80 ...)
tsrclo  .byte <(tpage0c + TROWS), <(tpage1c + TROWS)
tsrchi  .byte >(tpage0c + TROWS), >(tpage1c + TROWS)
tsrcklo .byte <(tpage0k + TROWS), <(tpage1k + TROWS)
tsrckhi .byte >(tpage0k + TROWS), >(tpage1k + TROWS)
tdstlo  .byte <(SCR_SCREEN + T_PAGE_TOP*40 + TROWS)
tdsthi  .byte >(SCR_SCREEN + T_PAGE_TOP*40 + TROWS)

; The scroller on row 24: a pixel a frame to the left. When the fine
; scroll runs out the row moves a character and the next one comes in;
; the colours run through twave across the row (~1000 cycles at most).
T_SPLIT  = 51 + T_PROMPT_ROW*8 - 1   ; 242: the line before the row
tscroll dec t_sx
        bpl tswave
        lda #7
        sta t_sx
        ldx #0                  ; the row a character left
-       lda SCR_SCREEN+T_PROMPT_ROW*40+1,x
        sta SCR_SCREEN+T_PROMPT_ROW*40,x
        inx
        cpx #39
        bne -
        ldy #0
        lda (t_tp),y
        cmp #$ff                ; the end: round again
        bne +
        lda #<tscrolltext
        sta t_tp
        lda #>tscrolltext
        sta t_tp+1
        lda (t_tp),y
+       sta SCR_SCREEN+T_PROMPT_ROW*40+39
        inc t_tp
        bne tswave
        inc t_tp+1
tswave  lda tframe              ; colour wave, moving the text's way
        lsr a
        sta t_tmp
        ldx #39
-       txa
        clc
        adc t_tmp
        and #15
        tay
        lda twave,y
        sta SCR_COLRAM+T_PROMPT_ROW*40,x
        dex
        bpl -
        rts
; the wave's 16 colours, indexed by (column + frame / 2) & 15
twave   .byte 1, 1, 15, 15, 12, 12, 15, 15, 1, 1, 3, 3, 14, 14, 3, 3

; The bars' colours for the next frame, a line each: the wall colour, then
; every bar of tbardef (the farthest first) at its place on the sine. Page
; 1 (the keys): no bars. tbardef (title.inc), a bar each: two sine phases,
; then its colours a line each, ended by a byte with bit 7 set; its top
; line is tsin[2 * frame + phase 0] + tsin[3 * frame + phase 1] / 2.
tbuild  lda #SCR_WALL_BG
        ldx #T_BAR_LINES-1
-       sta tbuf,x
        dex
        bpl -
        lda tpage
        beq +
        rts
+       ldx #0
tbnext  lda tframe
        asl a
        clc
        adc tbardef,x
        tay
        lda tsin,y
        sta t_tmp
        lda tframe
        asl a
        clc
        adc tframe
        clc
        adc tbardef+1,x
        tay
        lda tsin,y
        lsr a
        clc
        adc t_tmp
        tay                     ; the bar's top line
-       lda tbardef+2,x
        bmi +                   ; (the bar's end)
        sta tbuf,y
        iny
        inx
        bne -                   ; (always)
+       inx                     ; past its phases and the end: the next bar
        inx
        inx
        cpx #tbardef_end-tbardef
        bne tbnext
        rts

tpage   .byte 0                 ; the page shown (or being wiped in)
twrow   .byte 0                 ; the next row of the wipe; T_PAGE_ROWS: none
ttime   .word 0                 ; frames left on this page
tstate  .byte 0                 ; the keys: see tkeys
tframe  .byte 0
title_endline .byte 0
title_quit .byte 0

;------------------------------------------------------------------- bars
; catsim64's title bars (title.asm), moved down behind the logo: lines
; T_BAR_TOP to T_BAR_END-1, border and background, then the wall colour.
; Every colour is written in the horizontal blank before its line, so
; nothing shows: cycle-exact from a jitter-free start.
; Cycles count from 0 = the first one a read sees the new $d012 in.
;   sync    the poll finds line T_BAR_TOP-4 with its read at cycle 0-6;
;           three more reads, each a line later at the very end of the
;           line, tell the late from the early and the early wait 4, 2, 1
;           more. These four lines must not be bad lines (title.py checks)
;           and no sprite may be on them.
;   a line  63 cycles, $d021 written at cycle 56, $d020 at 60
;   a bad   line (51 + 8n) halts the CPU from cycle 12 to 54: the line
;           before it runs straight into the halt, the writes wait in it
;           and land at 57 and 61, and the seven lines after are exact
; The colours are tbuf's, a line each, built by tbuild a frame ahead. The
; routine and tbuf sit in one page: a branch or an index crossing a page
; would cost a cycle.
TB_SIZE  = 136                  ; tbars' length, at most

        .if (>*) != (>(* + TB_SIZE + T_BAR_LINES - 1))
        .align 256
        .fi
tbars   ldx #T_BAR_TOP-4
-       cpx $d012
        bne -
        ldy #7                  ; 54 cycles: the read 60 after the poll's
        jsr tdly
        nop
        nop
        nop
        cpx $d012
        bne +
        nop                     ; still this line: early, 4 more
        bit t_tmp
+       inx
        ldy #7                  ; 52
        jsr tdly
        nop
        nop
        cpx $d012
        bne +
        bit t_tmp                 ; 2 more
+       inx
        ldy #8                  ; 53
        jsr tdly
        cpx $d012
        bne +
        nop                     ; 1 more
+       ldx #T_BAD0-(T_BAR_TOP-1)   ; cycle 4 of line T_BAR_TOP-1; lines to the bad line
        ldy #0
        nop
        nop
        nop
        nop
        jmp tline
tbar    lda tbuf,y              ; 49
        sta $d021               ; written at 56
        sta $d020               ; and 60
        iny                     ; 61
        dex                     ; 0
        beq tbad
        jsr trts                ; 4
        bit t_tmp
tline   dec t_cnt                ; 19
        beq tend
        jsr trts                ; 26
        nop
        nop
        nop
        nop
        jmp tbar
tbad    lda tbuf,y              ; 5 of a bad line: the colour after its own
        ldx #7
        sta $d021               ; 11: halted in it until 55, written at 57
        sta $d020               ; and 61
        iny                     ; 62
        jsr trts                ; 1
        bit t_tmp
        jmp tline
tend    ldx #4                  ; 27 of line T_BAR_END-1: the wall from the next
-       dex
        bne -
        bit t_tmp
        lda #SCR_WALL_BG
        sta $d021               ; written at 56
        sta $d020               ; and 60
        rts
tdly    dey                     ; ldy #n, jsr tdly: 13+5n cycles
        bne tdly
trts    rts
tbars_end
tbuf    .fill T_BAR_LINES       ; the bars' colours, a line each

        .cerror tbars_end - tbars > TB_SIZE, "TB_SIZE too small"
        .cerror (>tbars) != (>(tbuf + T_BAR_LINES - 1)), "tbars/tbuf cross a page"

        .include "../gen/title.inc"
