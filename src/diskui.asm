; ------------------------------------------------------------------ disk page
; S or L (or a click on the disk icon on the panel's bottom line) opens a
; page over rows 12-24, the panel saved in helpbuf (as the help does). The
; band plays on while it is up; the music pauses only during disk I/O.
;
;   row 12     frame " Disk  drive 8"
;   14-20      a floppy (columns 2-9): a click re-reads the directory
;   13         the disk's name and ID
;   14-19      6 files of the directory (blocks, "NAME", type), the selected
;              one bold white with a cyan > at column 11; scroll arrows at
;              column 37 (rows 14 / 19) when there are more
;   20         "NNN blocks free."
;   21         Name: the name to load / save / delete (typed, or the file
;              selected), max 16 characters
;   23         Load  Save  Delete  Dir  Back  New
;   24         a hint, a message, "Overwrite NAME?  Yes  No", or New's
;              "This slot  All slots  Defaults  No"
;
; Keys: letters, digits, space, + - . type the name, DEL deletes; CRSR
; up/down select a file; RETURN Load, SHIFT+RETURN Save, F1 Dir, F7 Delete,
; RUN/STOP back. Asking: Y / N (or a click on Yes / No); New: T / A / D,
; N or RUN/STOP no.
;
; The directory: OPEN "$" on drive 8 (secondary 0) and CHRIN (the BASIC
; listing: load address, then per line link, blocks, text, 0), parsed by
; dir_parse (or from memory: dir_parsebuf, for tools/edittest.py), each
; line by dir_line; with CatBoot's drive code waiting,
; catdrive.asm builds the same lines from the raw sectors. Up to DMAX
; files are kept.
;
; Zero page: dp ($fb-$fc), dc ($fd-$fe), free in the main program (the
; disk code saves and restores all of it anyway).

        .enc "none"
DMAX    = 48                    ; files kept
DVIS    = 6                     ; files shown
DROW    = 14                    ; the first file's row
DLINE   = 40                    ; a listing line's text kept
dp      = $fb
dc      = $fd

K_Y     = 3*8+1                 ; (matrix codes, as catsynth.asm's K_*)
K_D     = 2*8+2
K_N     = 4*8+7

; ------------------------------------------------------------------ open / close
; S, L, the disk icon: the page up and the directory read (once up: nothing)
disk_open
        lda diskon
        bne +
        jsr dpage_show
        jmp dir_reload
+       rts

; the panel saved, the page drawn (no disk I/O)
dpage_show
        ldx #0                  ; rows 12-24 (520 bytes, 4 x 130): screen to
-       .for r = 0, r < 520, r += 130   ; helpbuf, colours to helpbuf+520
        lda SCR_SCREEN + 12*40 + r,x
        sta helpbuf + r,x
        lda SCR_COLRAM + 12*40 + r,x
        sta helpbuf + 520 + r,x
        lda #$20
        sta SCR_SCREEN + 12*40 + r,x
        lda #C_LGR
        sta SCR_COLRAM + 12*40 + r,x
        .next
        inx
        cpx #130
        bne -
        lda #1
        sta diskon
        lda #0
        sta dstate
        ldx #38                 ; the frame
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
        ldx #13                 ; the frame's sides, rows 13-21
-       jsr drow
        lda #G_V
        ldy #0
        sta (cp),y
        ldy #39
        sta (cp),y
        inx
        cpx #22
        bne -
        ldx #<dpgtext
        ldy #>dpgtext
        jsr dputs
        jsr dlist_draw
        jsr dflush
        jmp dhint

; RUN/STOP, Back: the panel back as it was
disk_close
        ldx #0
-       .for r = 0, r < 520, r += 130
        lda helpbuf + r,x
        sta SCR_SCREEN + 12*40 + r,x
        lda helpbuf + 520 + r,x
        sta SCR_COLRAM + 12*40 + r,x
        .next
        inx
        cpx #130
        bne -
        ldx #39                 ; row 14 without a playhead (it moved on)
-       lda r14buf,x
        sta SCR_SCREEN + HEADROW*40,x
        lda #C_LGR
        sta SCR_COLRAM + HEADROW*40,x
        dex
        bpl -
        lda #0
        sta diskon
        lda joy                 ; a fire that closed it is no tap (only
        and #$10                ; then: closed by a key or the mouse, the
        beq +                   ; next fire tap is a tap)
        sta fused
+
        lda #$ff
        sta lstep2
        sta cursat
        lda #$80
        sta dirty
        rts

; ------------------------------------------------------------------ keys
; once a frame while the page is up (catsynth.asm dispatch): all the keys
dkeys   lda dstate
        beq dk0
        cmp #3                  ; New?: SHIFT+T this slot, SHIFT+A all,
        bne dk1                 ; SHIFT+D defaults (plain letters: nothing,
        jsr shifted             ; they are the Name field's)
        beq dknn
        #pressed K_T
        beq +
        jmp dnslot
+       #pressed K_A
        beq +
        jmp dnallq
+       #pressed K_D
        beq dknn
        jmp dndefq
dknn    #pressed K_N
        bne +
        #pressed K_STOP
        beq dk9n
+       jmp dno
dk9n    rts
dk1     #pressed K_Y            ; asking: Y / N (RUN/STOP: no)
        beq +
        jmp dyes
+       #pressed K_N
        bne +
        #pressed K_STOP
        beq dk9
+       jmp dno
dk0     #pressed K_STOP
        beq +
        jmp disk_close
+       #pressed K_RETURN
        beq ++
        jsr shifted
        beq +
        jmp dsave
+       jmp dload
+       #pressed K_F1
        beq +
        jmp dir_reload
+       #pressed K_F7
        beq +
        jmp ddelete
+       #pressed K_CRSRUD
        beq ++
        jsr shifted
        beq +
        jmp dselup
+       jmp dseldn
+       #pressed K_DEL
        beq +
        jmp dbacksp
+       ldx #7                  ; the name's characters
dkcol   lda knew,x
        beq dknext
        stx dkx
        txa                     ; Y = column * 8 + the lowest row bit set
        asl a                   ; (one key a column a frame)
        asl a
        asl a
        tay
        lda knew,x
-       lsr a
        bcs +
        iny
        bne -
+       lda keypet,y
        beq +
        jsr dtypech
+       ldx dkx
dknext  dex
        bpl dkcol
dk9     rts
dkx     .byte 0

; A = a PETSCII character: onto the name (16 at most)
dtypech ldx nlen
        cpx #16
        bcs +
        sta nbuf,x
        inc nlen
        jmp dedited
+       rts

; DEL: the name's last character off
dbacksp lda nlen
        beq dbs9
        dec nlen
dedited lda dsel                ; edited: no file selected
        jsr dmarkf
        lda #$ff
        sta dsel
        lda dmask+1             ; the name redrawn
        ora #1
        sta dmask+1
        rts
dbs9    rts

; the C64's keys (column * 8 + row) as PETSCII for a name; 0: none
keypet  .byte 0, 0, 0, 0, 0, 0, 0, 0    ; (column 0: DEL, RETURN, CRSR, F keys)
        .text "3wa4zse", 0      ; (64tass -a: lower case = PETSCII $41-$5a)
        .text "5rd6cftx"
        .text "7yg8bhuv"
        .text "9ij0mkon"
        .text "+pl-.", 0, 0, 0
        .byte 0, 0, 0, 0, 0, 0, 0, 0
        .text "1", 0, 0, "2 ", 0, "q", 0

; ------------------------------------------------------------------ clicks
; from ui_click: X = column, Y = row
dclick  lda dstate
        beq dc0
        cmp #3                  ; New?: This slot (6-14), All slots (16-24),
        bne dcyn                ; Defaults (26-32), else no (No sits under
        cpy #24                 ; the New button: a second click there is
        bne dcnno               ; a no); row 24 only
        cpx #6
        bcc dcnno
        cpx #15
        bcs +
        jmp dnslot
+       cpx #16
        bcc dcnno
        cpx #25
        bcs +
        jmp dnallq
+       cpx #26
        bcc dcnno
        cpx #33
        bcs dcnno
        jmp dndefq
dcnno   jmp dno
dcyn    cpy #24                 ; asking: Yes (29-33), No (34-38), else no
        bne +
        cpx #29
        bcc +
        cpx #34
        bcs +
        jmp dyes
+       jmp dno
dc0     cpy #23                 ; browsing: row 23, the buttons
        bne dc2
        ldy #NBTN-1             ; the buttons
-       txa
        cmp btnx0,y
        bcc +
        cmp btnx1,y
        bcc dcbtn
+       dey
        bpl -
        rts
dcbtn   lda btnlo,y             ; button Y: jump to its routine
        sta gp
        lda btnhi,y
        sta gp+1
        jmp (gp)
dc2     cpy #DROW               ; rows 14-20: the floppy, the files
        bcc dc9
        cpy #21
        bcs dc9
        cpx #10                 ; the floppy (2-9): Dir
        bcs +
        cpx #2
        bcc dc9
        jmp dir_reload
+       cpy #DROW+DVIS
        bcs dc9
        cpx #37                 ; the scroll arrows
        bne +
        cpy #DROW
        beq dscrup
        cpy #DROW+DVIS-1
        beq dscrdn
dc9     rts
+       bcs dc9                 ; (C from cpx #37: right of the arrows)
        cpx #11                 ; a file: selected, its name to the field
        bcc dc9
        tya
        sec
        sbc #DROW
        clc
        adc dtop
        cmp dcount              ; (a row past the last file: nothing)
        bcs dc9
        jmp dselect

; row 23's buttons: column from (btnx0) to before (btnx1), and the routine
NBTN    = 6
btnx0   .byte 1, 7, 13, 21, 26, 33
btnx1   .byte 6, 12, 20, 25, 31, 37
btnlo   .byte <dload, <dsave, <ddelete, <dir_reload, <disk_close, <dnew
btnhi   .byte >dload, >dsave, >ddelete, >dir_reload, >disk_close, >dnew

; a click on the scroll arrows: the list a file up / down
dscrup  lda dtop
        beq +
        dec dtop
        jmp dmrows
+       rts
dscrdn  lda dtop
        clc
        adc #DVIS
        cmp dcount
        bcs +
        inc dtop
        jmp dmrows
+       rts
; all file rows and the scroll column marked for redrawing
dmrows  lda dmask               ; the file rows and the scroll column
        ora #$7e
        sta dmask
        lda dmask+1
        ora #2
        sta dmask+1
        rts

; CRSR: the file before / after (none selected: the first)
dselup  lda dsel
        cmp #$ff
        beq +
        cmp #0
        beq dsl9
        sec
        sbc #1
        jmp dselect
dseldn  lda dsel
        cmp #$ff
        bne ++
+       lda dcount
        beq dsl9
        lda #0
        jmp dselect
+       clc
        adc #1
        cmp dcount
        bcs dsl9
; A = a file: selected (scrolled into view), its name into the field
dselect pha
        lda dsel                ; the old one's row
        jsr dmarkf
        pla
        sta dsel
        jsr dmarkf              ; the new one's
        lda dtop
        sta dotop
        lda dsel                ; above the view: it is the top one
        cmp dtop
        bcs +
        sta dtop
+       sec                     ; below it: the bottom one (dtop = dsel - 5)
        sbc #DVIS-1
        bcc +
        cmp dtop
        bcc +
        sta dtop
+       lda dtop
        cmp dotop
        beq +
        jsr dmrows              ; scrolled: all rows
+       lda dmask+1
        ora #1
        sta dmask+1
        lda dsel                ; the name (up to 16, or its 0) to the field
        jsr dptr
        ldy #0
-       lda (dp),y
        beq +
        sta nbuf,y
        iny
        cpy #16
        bne -
+       sty nlen
        jmp dhint
dsl9    rts

; ------------------------------------------------------------------ actions
; Load: the file named into the open slot; the page closes, the song plays
dload   lda nlen
        bne +
        jmp dnoname
+       jsr sedited             ; changes not saved in this slot: asked
        beq dloadgo             ; first (dyes: dloadgo)
        lda #6
        sta dstate
        ldx #<dm_changes
        ldy #>dm_changes
        lda #C_YEL
        jsr dmsg
        ldx #<dpgyesno
        ldy #>dpgyesno
        jmp dputs
dloadgo ldx #<dm_loading
        ldy #>dm_loading
        jsr dmsgw
        jsr dname
        .if !WEB
        lda cd_on               ; CatBoot's drive code: the band plays on
        beq dlkern
        jsr cd_loadn
        bcc dlok
        ldx cd_on               ; (still on: the file came, not a song)
        bne dlerr
        .fi
dlkern  jsr dio_begin           ; the KERNAL's way: the music paused
        jsr disk_loadn
        jsr dio_end
        bcc dlok
dlerr   jmp derror
dlok    jsr disk_close          ; the song in the open slot, with the file's
        jsr dslname             ; name, playing, the panel back
        jsr sclean              ; (as on the disk: no changes)
        lda #0
        sta pslot
        sta pstyle
        lda #1
        sta running
        jsr slot_play
        ldx #<msg_loaded
        ldy #>msg_loaded
        jmp message

; Save: the open slot's song as the file named (on the disk already: asked
; first, dsavego after a yes); the directory read again
dsave   lda nlen
        bne +
        jmp dnoname
+       jsr dwild               ; (* ? , = : in the name: refused)
        bcs dsv9
        jsr dfind               ; in the list: ask first (not over a file
        bcs dsvnew              ; that isn't a song: the program, a SEQ...)
        jsr dsong
        bcc dsvask
        ldx #<dm_notover
        ldy #>dm_notover
        jmp dmsgerr
dsvask  lda #1
        sta dstate
        ldx #<dm_overwr
        ldy #>dm_overwr
        jmp dask
dsvnew  lda #0                  ; not in the list (it may be longer than
        .byte $2c               ; DMAX, or another disk): saved only if
dsavego lda #1                  ; the drive has no such file (then asked)
        sta dsvmode
        ldx #<dm_saving
        ldy #>dm_saving
        jsr dmsgw
        jsr dio_begin
        jsr dname
        lda dsvmode
        beq +
        jsr disk_saven          ; (after a yes: replaced, safely)
        jmp ++
+       jsr disk_savenew
+       jsr dio_end
        bcc +
        cmp #DE_EXISTS
        beq dsvask
        jmp derror
+       jsr dslname             ; the open slot takes the name
        jsr sclean              ; (saved: no changes)
        jsr dir_reload          ; the directory again, the new file selected
        bcs dsv9
        jsr dfind
        bcs dsv8
        txa
        jsr dselect
dsv8    ldx #<dm_saved
        ldy #>dm_saved
        jmp dmsgok
dsv9    rts

; Delete: the file named, after a yes (ddelgo); the directory read again
ddelete lda nlen
        bne +
        jmp dnoname
+       jsr dwild               ; (a pattern would scratch many files)
        bcc +
        rts
+       lda #2
        sta dstate
        jsr dfind               ; (in the list and not a song: said so)
        bcs +
        jsr dsong
        bcc +
        ldx #<dm_delns
        ldy #>dm_delns
        jmp dask
+       ldx #<dm_delete
        ldy #>dm_delete
        jmp dask

; X = a file in the list: C clear when it looks like a song (a PRG of 1 or
; 2 blocks: a song file is at most 258 bytes)
dsong   lda dtype,x
        cmp #2
        bne dsg9
        txa
        sta dtx
        asl a
        adc dtx                 ; (X * 3: its blocks' 3 screen codes)
        tay
        lda dbtxt,y             ; (the digits are stored with bit 7 set:
        and #$7f                ; the UI font's bold)
        cmp #$20
        bne dsg9
        lda dbtxt+1,y
        and #$7f
        cmp #$20
        bne dsg9
        lda dbtxt+2,y
        and #$7f
        cmp #$31
        beq +
        cmp #$32
        bne dsg9
+       clc
        rts
dsg9    sec
        rts
ddelgo  ldx #<dm_deleting
        ldy #>dm_deleting
        jsr dmsgw
        jsr dio_begin
        jsr dname
        jsr disk_scratch
        jsr dio_end
        bcc +
        jmp derror
+       jsr dir_reload
        bcs +
        ldx #<dm_deleted
        ldy #>dm_deleted
        jmp dmsgok
+       rts

; a yes / a no to the question on row 24 (dstate 1 overwrite, 2 delete,
; 3 new: no only)
dyes    lda dstate
        ldx #0
        stx dstate
        cmp #1
        bne +
        jmp dsavego
+       cmp #4
        bne +
        jmp dnall
+       cmp #5
        bne +
        jmp dndef
+       cmp #6
        bne +
        jmp dloadgo
+       jmp ddelgo
dno     lda #0
        sta dstate
        jmp dhint

; New (slots.asm): a new empty song in this slot, in all ten, or the ten
; styles' songs back. Asked first (dstate 3); the page closes, the panel
; shows the open slot playing from the top.
dnew    lda #3
        sta dstate
        ldx #<dm_newq
        ldy #>dm_newq
        lda #C_YEL
        jsr dmsg
        ldx #<dpgnew
        ldy #>dpgnew
        jmp dputs

; All slots, Defaults: asked once more (dstate 4, 5: dyes)
dnallq  lda #4
        .byte $2c
dndefq  lda #5
        sta dstate
        ldx #<dm_allq
        ldy #>dm_allq
        lda #C_YEL
        jsr dmsg
        ldx #<dpgyesno
        ldy #>dpgyesno
        jmp dputs

; This slot / All slots / Defaults
dnslot  jsr dnbegin
        jsr slot_blank
        jsr sclean
        ldx #<msg_newslot
        ldy #>msg_newslot
        jmp dnend
dnall   jsr dnbegin
        ldx curslot             ; (the open one put back: each slot keeps
        jsr slot_put            ; its style)
        ldx #0
-       stx dni
        jsr slot_fetch
        jsr slot_blank
        ldx dni
        jsr smark
        ldx dni
        jsr slot_put
        ldx dni
        inx
        cpx #NSLOTS
        bne -
        ldx curslot
        jsr slot_fetch
        ldx #<msg_newall
        ldy #>msg_newall
        jmp dnend
dndef   jsr dnbegin
        jsr slots_defaults
        ldx curslot
        jsr slot_fetch
        ldx #<msg_defs
        ldy #>msg_defs
        jmp dnend
; the page closed, switches waiting called off
dnbegin lda #0
        sta dstate
        sta pslot
        sta pstyle
        jsr sfx_stop            ; (All slots and Defaults take 7-11 frames:
        jmp disk_close          ; no notes held meanwhile)
; X/Y = a message: the open slot plays, the message shown
dnend   stx dnmsg
        sty dnmsg+1
        jsr slot_play
        ldx dnmsg
        ldy dnmsg+1
        jmp message
dni     .byte 0                 ; dnall's slot
dnmsg   .word 0                 ; dnend's message

; the name field -> the open slot's name (slots.asm sname)
dslname lda nlen
        sta sname
        ldx #0
-       cpx nlen
        beq +
        lda nbuf,x
        sta sname+1,x
        inx
        bne -
+       rts

; an empty name field: say so
dnoname ldx #<dm_noname
        ldy #>dm_noname
        jmp dmsgerr

; C set (and said so) when the name field holds a character the drive
; reads as a pattern or a separator: * ? , = : " $ @ / (a name picked from
; the list can; "S0:" with it would scratch other files too, "$" reads the
; directory, "@" is the 1541's save-and-replace), or anything odd: control
; codes, shifted letters, graphics (outside PETSCII $20-$5f), which the
; drive may take apart in its own ways
dwild   ldx nlen
-       dex
        bmi dw9                 ; (C clear: none)
        lda nbuf,x
        cmp #$20                ; (control codes)
        bcc dwbad
        cmp #$60                ; (shifted letters, graphics, $a0)
        bcs dwbad
        ldy #len(DWILD)-1
-       cmp dwilds,y
        beq dwbad
        dey
        bpl -
        bmi --
dwbad   ldx #<dm_wild
        ldy #>dm_wild
        jsr dmsgerr
        sec
        rts
dw9     clc
        rts
DWILD   = [$2a, $3f, $2c, $3d, $3a, $22, $24, $40, $2f]   ; * ? , = : " $ @ /
dwilds  .byte DWILD
dsvmode .byte 0                 ; dsave: 0 a new file, 1 replace (after a yes)
dmsgdly .byte 15                ; dio_begin: frames the message shows first
                                ; (the tests: 0)

; the name field -> disk_setname
dname   ldx #<nbuf
        ldy #>nbuf
        lda nlen
        jmp disk_setname

; X = the file named in the field (C clear), C set: none
dfind   ldx dcount              ; (the last one first)
dfnext  dex
        bmi dfno
        txa
        jsr dptr
        ldy #0
-       cpy nlen
        beq dflast
        lda (dp),y
        cmp nbuf,y
        bne dfnext
        iny
        bne -
dflast  cpy #16                 ; all 16, or the stored name ends here
        beq +
        lda (dp),y
        bne dfnext
+       clc
        rts
dfno    sec
        rts

; the music paused, the interrupts off around disk I/O (C and A kept after)
dio_begin
        .if !WEB
        jsr cd_quit             ; (CatBoot's drive code: the DOS back first)
        .fi
        jsr sfx_stop
        ldx dmsgdly             ; the message ("Loading..."), the panel as it
        beq +                   ; is: 15 frames to be read before the screen
-       lda #$fa                ; blanks for the drive
-       cmp $d012
        bne -
-       cmp $d012
        beq -
        dex
        bne --
+
        lda #0                  ; (a beat pulse under way: not its colour
        sta ptime               ; round the blanked screen while the drive
        lda #SCR_WALL_BG        ; works)
        sta $d020
        lda running
        sta dwasrun
        lda #0
        sta running
        jmp ui_irqoff           ; (ui.asm: the KERNAL's IRQ handler back)
dio_end php
        pha
        jsr ui_irqon
        lda dwasrun
        sta running
        pla
        plp
        cli                     ; (plp brought back the disk code's sei)
        rts

; ------------------------------------------------------------------ directory
; read it again: the list (empty after an error) and a message. C set: an
; error (shown).
dir_reload
        lda #0
        sta dstate
        ldx #<dm_reading
        ldy #>dm_reading
        jsr dmsgw
        .if !WEB
        lda cd_on               ; CatBoot's drive code: the band plays on
        beq +
        jsr cd_dirread
        bcc dirrd9              ; (failed: the drive is the DOS's again)
+
        .fi
        jsr dio_begin
        jsr dir_read
        jsr dio_end
dirrd9  php
        pha
        lda #0
        sta dtop
        lda #$ff
        sta dsel
        jsr dlist_draw
        jsr dflush
        pla
        plp
        bcs +
        jsr dhint
        clc
        rts
+       jsr derror
        sec
        rts

; KERNAL: "$" -> dir_parse. Out as disk_save: C, A = disk_err
dir_read
        lda #0
        sta disk_dos
        sta disk_st
        sta dvalid
        jsr dir_clear
        jsr dk_enter
        lda #1
        ldx #<dk_dollar
        ldy #>dk_dollar
        jsr K_SETNAM
        lda #2
        ldx #DISK_DEV
        ldy #0
        jsr K_SETLFS
        jsr K_OPEN
        bcc +
        jmp dk_kerr
+       lda $90                 ; (ST bit 7: device not present)
        bpl +
        lda #2
        jsr K_CLOSE
        jmp dk_dnp
+       ldx #2
        jsr K_CHKIN
        bcc +
        pha
        lda #2
        jsr K_CLOSE
        pla
        jmp dk_kerr
+       lda #<dir_chrin         ; dir_parse reads with CHRIN
        sta dir_get+1
        lda #>dir_chrin
        sta dir_get+2
        jsr dir_parse
        jsr K_CLRCHN
        lda #2
        jsr K_CLOSE
        lda disk_st
        bpl +
        jmp dk_dnp
+       jsr dk_status
        bcc +
        jmp dk_kerr
+       lda disk_dos
        cmp #20
        bcc +
        jmp dk_drverr
+       lda dperr               ; a serial error during the listing (disk_dos
        beq +                   ; < 20 here: DE_DRIVE)
        jmp dk_drverr
+       inc dvalid
        jmp dk_ok
dk_dollar .text "$"

; a byte from the "$" file: A, C set when there is none (the end before,
; or an error: dperr)
dir_chrin
        lda deof
        bne dch9
        jsr K_CHRIN
        pha
        lda $90
        sta disk_st
        and #$83                ; time-outs, no device: no byte
        bne dch8
        lda $90                 ; (ST bit 6: EOI)
        and #$40
        sta deof                ; the last byte
        pla
        clc
        rts
dch8    sta dperr
        sta deof
        pla
dch9    sec
        rts

; the test hook (tools/edittest.py): dir_parse from memory, dsrc (dlen
; bytes; dir_bget)
dir_parsebuf
        lda #<dir_bget
        sta dir_get+1
        lda #>dir_bget
        sta dir_get+2
        jsr dir_clear
        jmp dir_parse
; a byte from dsrc, C set when dlen ran out
dir_bget
        lda dlen
        ora dlen+1
        beq dch9
        lda dlen
        bne +
        dec dlen+1
+       dec dlen
dsrc = * + 1                    ; (the operand: the next byte's address)
        lda $ffff
        inc dsrc
        bne +
        inc dsrc+1
+       clc
        rts
dlen    .word 0

dir_get jmp dir_chrin           ; (the source: dir_chrin or dir_bget)

; an empty list, no header, no blocks free; the parse's flags clear
dir_clear
        lda #0
        sta dcount
        sta deof
        sta dperr
        sta dfree
        sta dfree+1
        ldx #20
-       sta dhdr,x              ; (and did)
        dex
        bpl -
        rts

; the listing: load address; per line link (0: the end), blocks, text, 0.
; Line 0: the disk's name and ID; a line with "NAME": a file; one with no
; quote: the blocks free.
dir_parse
        lda #0
        sta dline
        jsr dir_get             ; the load address
        bcs dp9
        jsr dir_get
        bcs dp9
dpline  jsr dir_get             ; the link
        bcs dp9
        sta dlink
        jsr dir_get
        bcs dp9
        ora dlink
        beq dp9
        jsr dir_get             ; the blocks
        bcs dp9
        sta dblk
        jsr dir_get
        bcs dp9
        sta dblk+1
        ldx #0
dptext  jsr dir_get
        bcs dp9                 ; (a line cut short: dropped)
        cmp #0
        beq dpdone
        cpx #DLINE
        bcs dptext
        sta dlbuf,x
        inx
        bne dptext
dpdone  stx dllen
        lda #0
        sta dlbuf,x
        sta dlbuf+1,x
        sta dlbuf+2,x
        jsr dir_line
        inc dline               ; (up to 255: only line 0 is special)
        bne dpline
        dec dline
        jmp dpline
dp9     rts

; the line in dlbuf (dllen bytes; dline, dblk): the header, a file or the
; blocks free
dir_line
        ldx #0                  ; the first quote
-       cpx dllen
        bcs dlfree
        lda dlbuf,x
        inx
        cmp #$22
        bne -
        lda dline
        bne dlfile
        ldy #0                  ; line 0: the disk's name
-       cpx dllen
        bcs dlh9
        lda dlbuf,x
        inx
        cmp #$22
        beq dlhid
        cpy #16
        bcs -
        sta dhdr,y
        iny
        bne -
dlhid   inx                     ; " ", then the ID ("2A 2A")
        ldy #0
-       cpx dllen
        bcs dlh9
        lda dlbuf,x
        sta did,y
        inx
        iny
        cpy #5
        bne -
dlh9    ldy #15                 ; the name's trailing spaces off
-       lda dhdr,y
        beq +
        cmp #$20
        bne dlh8
        lda #0
        sta dhdr,y
+       dey
        bpl -
dlh8    rts
dlfree  lda dblk
        sta dfree
        lda dblk+1
        sta dfree+1
        rts
dlfile  lda dcount              ; a file: its name into dnames (DMAX kept)
        cmp #DMAX
        bcs dlh8
        jsr dptr
        ldy #15
        lda #0
-       sta (dp),y
        dey
        bpl -
        iny
-       cpx dllen
        bcs dlf2
        lda dlbuf,x
        inx
        cmp #$22
        beq dlf2
        cpy #16
        bcs -
        sta (dp),y
        iny
        bne -
dlf2    cpx dllen               ; the type: past spaces and "*" (not closed)
        bcs dlf3
        lda dlbuf,x
        cmp #$20
        beq +
        cmp #$2a
        bne dlf3
+       inx
        bne dlf2
dlf3    stx dtx                 ; dtyn: the type's index in dtypes (5: none)
        ldy #0
        lda #0
dltyp   sta dtyn
        ldx dtx
        lda dlbuf,x
        cmp dtypes,y
        bne +
        lda dlbuf+1,x
        cmp dtypes+1,y
        bne +
        lda dlbuf+2,x
        cmp dtypes+2,y
        beq dlt9
+       iny
        iny
        iny
        lda dtyn
        clc
        adc #1
        cmp #5
        bne dltyp
        sta dtyn
dlt9    lda dtyn                ; a DEL of 0 blocks: a directory's art
        bne +                   ; line (like our own disk's), never a
        lda dblk                ; song: left out (its slot is used by
        ora dblk+1              ; the next)
        bne +
        rts
+       lda dtyn
        ldx dcount
        sta dtype,x
        jsr dblktxt
        inc dcount
        rts
; the file types, 3 characters each, by dtype: as the listing has them,
; and as shown (5: ???)
dtypes  .text "delseqprgusrrel"         ; (PETSCII $41-$5a)
        .enc "uireg"
dtypnam .text "DELSEQPRGUSRREL???"
        .enc "none"

; A = a file: dp on its name (dnames + A * 16)
dptr    sta dp
        lda #0
        sta dp+1
        .rept 4
        asl dp
        rol dp+1
        .endrept
        lda dp
        clc
        adc #<dnames
        sta dp
        lda dp+1
        adc #>dnames
        sta dp+1
        rts

; ------------------------------------------------------------------ drawing
; X = row: cp on it (screen), dc (colour); keeps X, Y
drow    lda rowlo,x
        sta cp
        sta dc
        lda rowhi,x
        sta cp+1
        clc
        adc #COLOFS
        sta dc+1
        rts

; A = a character at column Y in colour dcol (cp, dc); Y + 1
dch     sta (cp),y
        lda dcol
        sta (dc),y
        iny
        rts

; A = a PETSCII character -> its screen code (bold; + $80 regular); others
; (control codes, graphics) are "?"
pet2scr cmp #$20
        bcc p2q
        cmp #$40
        bcc p2r
        beq p2at
        cmp #$5b
        bcc p2r                 ; A-Z: $41-$5a as they are
        cmp #$60
        bcc p2m                 ; [ pound ] ^ <-: $1b-$1f
        cmp #$a0                ; shifted space
        beq p2sp
        cmp #$c1
        bcc p2q
        cmp #$db
        bcs p2q
p2m     and #$1f                ; shifted letters ($c1-$da): a-z
        rts
p2at    lda #0
        rts
p2sp    lda #$20
        rts
p2q     lda #$3f
p2r     rts

; X/Y = records (row, column, colour, screen codes, 0), $ff at the end
; (dpgtext, dpgnew, dpgyesno)
dputs   stx gp
        sty gp+1
dps1    ldy #0
        lda (gp),y
        cmp #$ff
        beq dps9
        tax
        jsr drow
        ldy #1
        lda (gp),y
        clc
        adc cp
        sta cp
        sta dc
        bcc +
        inc cp+1
        inc dc+1
+       ldy #2
        lda (gp),y
        sta dcol
        lda gp                  ; gp on the text
        clc
        adc #3
        sta gp
        bcc +
        inc gp+1
+       ldy #0
-       lda (gp),y
        beq +
        jsr dch
        bne -                   ; (Y not 0: always)
+       iny                     ; past the 0
        tya
        clc
        adc gp
        sta gp
        bcc dps1
        inc gp+1
        bne dps1
dps9    rts

; The directory's parts, drawn when marked in dmask (bit 0 the header,
; bits 1-6 the file rows, bit 7 the blocks free) and dmask+1 (bit 0 the
; name, bit 1 the scroll column), DPARTS a frame (disk_tick, from infos):
; each is ~1600-2100 cycles, ~6500 a frame at most.
DPARTS  = 4
dlist_draw
        lda #$ff
        sta dmask
        lda #3
        sta dmask+1
        rts

; once a frame while the page is up (ui.asm): up to DPARTS parts drawn
disk_tick
        lda #DPARTS
        sta dpn
-       lda #170                ; (a part is at most ~2300 cycles: one only
        jsr roomy               ; while the frame has room for it; the rest
        bcc +                   ; the next frame)
        jsr dpart
        bcs +
        dec dpn
        bne -
+       rts

; all marked parts now
dflush  jsr dpart
        bcc dflush
        rts

; the first marked part drawn; C set: none was
dpart   lda dmask
        bne dpt1
        lda dmask+1
        bne +
        sec
        rts
+       lsr a
        bcc +
        lda dmask+1
        and #$fe
        sta dmask+1
        jsr dname_draw
        clc
        rts
+       lda #0
        sta dmask+1
        jsr dscroll_draw
        clc
        rts
dpt1    ldx #0                  ; X = its lowest bit set: that one off
-       lsr a
        bcs +
        inx
        bne -
+       lda dmask
        and dbitoff,x
        sta dmask
        txa
        bne +
        jsr dhead_draw
        clc
        rts
+       cpx #7
        bne +
        jsr dfree_draw
        clc
        rts
+       dex                     ; bits 1-6: file rows 0-5
        txa
        jsr dfrow
        clc
        rts
dbitoff .byte $fe, $fd, $fb, $f7, $ef, $df, $bf, $7f    ; all but bit n

; A = a file: its row marked, if shown ($ff, none: never)
dmarkf  sec
        sbc dtop
        bcc +
        cmp #DVIS
        bcs +
        tax
        inx                     ; (row n: dmask bit n + 1)
        lda dmask
        ora dbiton,x
        sta dmask
+       rts
dbiton  .byte 1, 2, 4, 8, 16, 32, 64, 128              ; bit n

; X = row: columns 11 to A - 1 blank (cp, dc on the row)
dclr    sta dtx
        jsr drow
        ldy #11
        lda #$20
-       sta (cp),y
        iny
        cpy dtx
        bne -
        rts

; row 13: the disk's name and ID, bold white
dhead_draw
        ldx #13
        lda #39
        jsr dclr
        lda dvalid
        beq dhd9
        lda #C_WHT
        sta dcol
        ldy #12
        lda #$22
        jsr dch
        ldx #0
-       lda dhdr,x
        beq +
        jsr pet2scr
        jsr dch
        inx
        cpx #16
        bne -
+       lda #$22
        jsr dch
        lda #$20
        jsr dch
        ldx #0
-       lda did,x
        beq dhd9
        jsr pet2scr
        jsr dch
        inx
        cpx #5
        bne -
dhd9    rts

; A = 0-5: the file shown on that row (dtop + A): > if selected, blocks,
; "NAME" (regular light grey; the selected one bold white), type
dfrow   sta dli
        clc
        adc #DROW
        tax
        lda #37
        jsr dclr
        lda dli
        clc
        adc dtop
        sta dle
        cmp dcount
        bcc +
        rts
+       lda #$80                ; the weight, the colour (screen code
                                ; + $80: regular in the UI font)
        sta dwt
        lda #C_LGR
        sta dcol
        lda dle
        cmp dsel
        bne +
        lda #0
        sta dwt
        ldy #11
        lda #G_PLAY
        sta (cp),y
        lda #C_CYN
        sta (dc),y
        lda #C_WHT
        sta dcol
+       lda dle                 ; the blocks (3 screen codes, from the parse)
        asl a
        adc dle
        tax
        ldy #12
-       lda dbtxt,x
        sta (cp),y
        lda #C_GRY
        sta (dc),y
        inx
        iny
        cpy #15
        bne -
        lda dle
        jsr dptr
        ldy #0                  ; the name's screen codes
-       lda (dp),y
        beq +
        jsr pet2scr
        ora dwt
        sta dscr,y
        iny
        cpy #16
        bne -
+       sty dtx
        ldy #16
        lda #$22
        ora dwt
        sta dqt
        sta (cp),y
        lda dcol
        sta (dc),y
        iny
        ldx #0
-       cpx dtx
        beq +
        lda dscr,x
        sta (cp),y
        lda dcol
        sta (dc),y
        iny
        inx
        bne -
+       lda dqt
        sta (cp),y
        lda dcol
        sta (dc),y
        ldx dle                 ; the type
        lda dtype,x
        sta dtx
        asl a
        adc dtx                 ; * 3
        tax
        ldy #34
-       lda dtypnam,x
        sta (cp),y
        lda #C_GRY
        sta (dc),y
        inx
        iny
        cpy #37
        bne -
dfr9    rts

; column 37, rows 14-19: the arrows and a thumb when there are more files
dscroll_draw
        ldx #DROW
-       jsr drow
        ldy #37
        lda #$20
        sta (cp),y
        inx
        cpx #DROW+DVIS
        bne -
        lda dcount              ; (all on show: no arrows)
        cmp #DVIS+1
        bcc dsc9
        lda #C_LGR
        sta dcol
        ldx #DROW
        jsr drow
        ldy #37
        lda #G_UP
        jsr dch
        ldx #DROW+DVIS-1
        jsr drow
        ldy #37
        lda #G_DOWN
        jsr dch
        lda dcount              ; row 15 + dtop * 4 / (dcount - 5), 15-18
        sec
        sbc #DVIS-1
        sta dtx
        lda dtop
        asl a
        asl a
        ldx #DROW+1
-       cmp dtx
        bcc +
        sbc dtx
        inx
        bne -
+       jsr drow
        lda #C_GRY
        sta dcol
        ldy #37
        lda #G_CHECK
        jsr dch
dsc9    rts

; row 20: "NNN blocks free."
dfree_draw
        ldx #20
        lda #39
        jsr dclr
        lda dvalid
        beq dfd9
        lda dfree
        sta dnum
        lda dfree+1
        sta dnum+1
        jsr ddec
        lda #C_GRY
        sta dcol
        ldy #12
        ldx #0
-       lda ddig,x              ; no leading zeros
        cmp #$30
        bne +
        inx
        cpx #4
        bne -
+
-       lda ddig,x
        ora #$80
        jsr dch
        inx
        cpx #5
        bne -
        ldx #0
-       lda dm_free,x
        beq dfd9
        jsr dch
        inx
        bne -
dfd9    rts

; row 21: "Name" and the name (bold white), a block cursor
dname_draw
        ldx #21
        lda #39
        jsr dclr
        lda #C_GRY
        sta dcol
        ldy #12
        ldx #0
-       lda dm_name,x
        beq +
        jsr dch
        inx
        bne -
+       lda #C_WHT
        sta dcol
        ldy #17
        ldx #0
-       cpx nlen
        beq +
        lda nbuf,x
        jsr pet2scr
        jsr dch
        inx
        bne -
+       lda #G_FULL
        jmp dch

; the blocks of the file being parsed (dblk) -> dbtxt (3 screen codes,
; regular, leading zeros blank, over 999: 999)
dblktxt lda dblk
        sta dnum
        lda dblk+1
        sta dnum+1
        jsr ddec
        lda dcount
        asl a
        adc dcount
        tax
        lda ddig                ; (a ten-thousand or a thousand: not "0"
        ora ddig+1              ; ORed, $30)
        cmp #$30
        beq +
        lda #$39
        sta ddig+2
        sta ddig+3
        sta ddig+4
+       ldy #2                  ; the hundreds, tens, units; zeros blank but
-       lda ddig,y              ; the last
        cpy #4
        beq +
        cmp #$30
        bne +
        lda #$20
        sta dbtxt,x
        inx
        iny
        bne -
+
-       lda ddig,y
        ora #$80
        sta dbtxt,x
        inx
        iny
        cpy #5
        bne -
        rts

; dnum -> ddig: 5 digits (screen codes), by subtracting the powers of ten
; (dpowlo / dpowhi); dnum is 0 after
ddec    ldx #0
ddl     ldy #$30
-       lda dnum
        sec
        sbc dpowlo,x
        sta dtx
        lda dnum+1
        sbc dpowhi,x
        bcc +
        sta dnum+1
        lda dtx
        sta dnum
        iny
        bne -
+       tya
        sta ddig,x
        inx
        cpx #5
        bne ddl
        rts
dpowlo  .byte <10000, <1000, <100, <10, <1
dpowhi  .byte >10000, >1000, >100, >10, >1

; ------------------------------------------------------------------ row 24
; row 24: dhint the hint (grey); X/Y = a text: dmsgok light green, dmsgerr
; light red, dmsgw white (working...)
dhint   ldx #<dm_hint
        ldy #>dm_hint
        lda #C_GRY
        bne dmsg
dmsgok  lda #C_LGN
        bne dmsg
dmsgerr lda #C_LRD
        bne dmsg
dmsgw   lda #C_WHT
; X/Y = a 0-terminated text (screen codes), A = colour: row 24, column 1
dmsg    stx gp
        sty gp+1
        sta dcol
        ldx #24
        jsr drow
        ldy #39
        lda #$20
-       sta (cp),y
        dey
        bpl -
        ldy #0                  ; character i at column i + 1
-       lda (gp),y
        beq +
        iny
        sta (cp),y
        lda dcol
        sta (dc),y
        jmp -
+       rts

; X/Y = "Overwrite " / "Delete ": that, the name, "?", Yes and No
dask    stx gp
        sty gp+1
        ldy #0
-       lda (gp),y
        beq +
        sta dmbuf,y
        iny
        bne -
+       ldx #0
-       cpx nlen
        beq +
        lda nbuf,x
        jsr pet2scr
        sta dmbuf,y
        iny
        inx
        bne -
+       lda #$3f
        sta dmbuf,y
        lda #0
        sta dmbuf+1,y
        ldx #<dmbuf
        ldy #>dmbuf
        lda #C_YEL
        jsr dmsg
        ldx #<dpgyesno
        ldy #>dpgyesno
        jmp dputs

; A = disk_err: what went wrong, in words (others: "Disk error NN", the
; KERNAL's number or the drive's code)
derror  cmp #DE_BADFILE
        bne +
        ldx #<dm_notsong
        ldy #>dm_notsong
        jmp dmsgerr
+       cmp #4
        bne +
        ldx #<dm_notfound
        ldy #>dm_notfound
        jmp dmsgerr
+       cmp #5
        bne +
dnotrdy ldx #<dm_notready
        ldy #>dm_notready
        jmp dmsgerr
+       cmp #DE_DRIVE
        bne derrn
        lda disk_dos            ; 74 drive not ready, 72 disk full, 26 write
        cmp #74                 ; protect
        beq dnotrdy
        cmp #72
        bne +
        ldx #<dm_full
        ldy #>dm_full
        jmp dmsgerr
+       cmp #26
        bne +
        ldx #<dm_wprot
        ldy #>dm_wprot
        jmp dmsgerr
+       jmp derrn2
derrn                           ; a KERNAL error: its number
derrn2  sta dnum                ; "Disk error NN" (jmp derrn2: the drive's)
        lda #0
        sta dnum+1
        jsr ddec
        ldx #0
-       lda dm_err,x
        sta dmbuf,x
        beq +
        inx
        bne -
+       lda ddig+3              ; the last two digits
        sta dmbuf,x
        lda ddig+4
        sta dmbuf+1,x
        lda #0
        sta dmbuf+2,x
        ldx #<dmbuf
        ldy #>dmbuf
        jmp dmsgerr

; ------------------------------------------------------------------ texts
        .enc "screen"
dm_loading  .null "Loading..."
dm_saving   .null "Saving..."
dm_deleting .null "Deleting..."
dm_reading  .null "Reading..."
dm_saved    .null "Saved"
dm_deleted  .null "Deleted"
dm_overwr   .null "Overwrite "
dm_delete   .null "Delete "
dm_delns    .null "Not a song! Delete "
dm_notover  .null "Not a song there: another name"
dm_newq     .null "New:"
dm_allq     .null "Replace all ten songs?"
dm_changes  .null "Not saved! Load over it?"
dm_noname   .null "Type a name first"
dm_wild     .null "No $ * ? , = : / or odd signs here"
dm_notsong  .null "Not a CatSynth song"
dm_notfound .null "File not found"
dm_notready .null "Drive not ready"
dm_full     .null "Disk full"
dm_wprot    .null "Write protected"
dm_err      .null "Disk error "
        .enc "uireg"
dm_hint     .null "Click a song, then Load. RUN/STOP: back"
dm_free     .null " blocks free."
dm_name     .null "Name"
        .enc "none"

; the page's fixed parts: row, column, colour, text, 0 ... $ff
dpgtext .byte 12, 2, C_WHT
        .enc "screen"
        .null " Disk "
        .enc "none"
        .byte 12, 9, C_GRY
        .enc "uireg"
        .null "drive 8"
        .enc "none"
        .byte 15, 4, C_LBL, G_FLOP[0], G_FLOP[1], G_FLOP[2], G_FLOP[3], 0
        .byte 16, 4, C_LBL, G_FLOP[4], G_FLOP[5], G_FLOP[6], G_FLOP[7], 0
        .byte 17, 4, C_LBL, G_FLOP[8], G_FLOP[9], G_FLOP[10], G_FLOP[11], 0
        .byte 18, 4, C_LBL, G_FLOP[12], G_FLOP[13], G_FLOP[14], G_FLOP[15], 0
        .enc "screen"
        .byte 23, 1, C_GRN
        .null "Load"
        .byte 23, 7, C_YEL
        .null "Save"
        .byte 23, 13, C_LRD
        .null "Delete"
        .byte 23, 21, C_CYN
        .null "Dir"
        .byte 23, 26, C_WHT
        .null "Back"
        .byte 23, 33, C_LBL
        .null "New"
        .enc "none"
        .byte $ff
dpgnew                          ; New?: the choices (dnew)
        .enc "screen"
        .byte 24, 6, C_LGN
        .null "This slot"
        .byte 24, 16, C_LRD
        .null "All slots"
        .byte 24, 26, C_CYN
        .null "Defaults"
        .byte 24, 34, C_GRY
        .null "No"
        .enc "none"
        .byte $ff
dpgyesno
        .enc "screen"
        .byte 24, 30, C_LGN
        .null "Yes"
        .byte 24, 35, C_LRD
        .null "No"
        .enc "none"
        .byte $ff

; ------------------------------------------------------------------ state
G_CHECK = $66
diskon  .byte 0                 ; the page is up
dstate  .byte 0                 ; 0 browsing, 1 overwrite?, 2 delete?, 3 new?
dwasrun .byte 0                 ; running before the disk I/O
dvalid  .byte 0                 ; a directory was read
dcount  .byte 0                 ; files
dtop    .byte 0                 ; the first one shown
dsel    .byte $ff               ; the one selected ($ff: none)
dfree   .word 0
nlen    .byte 7                 ; the name field
nbuf    .text "catsong"
        .fill 16 - 7, 0
deof    .byte 0                 ; the parse: the last byte came (or an error)
dperr   .byte 0                 ; ...ST's error bits
dline   .byte 0                 ; ...the listing's line (to 255)
dlink   .byte 0                 ; ...the line link's low byte
dblk    .word 0                 ; ...the line's blocks
dllen   .byte 0                 ; ...its text's length in dlbuf
dtx     .byte 0                 ; a scratch
dtyn     .byte 0                ; the parse: the file's type
dli     .byte 0                 ; dfrow: the row 0-5
dotop   .byte 0                 ; dselect: dtop before
dle     .byte 0                 ; dfrow: the file
dwt     .byte 0                 ; dfrow: $80 regular, 0 bold
dqt     .byte 0                 ; dfrow: the quote's screen code
dpn     .byte 0                 ; disk_tick: parts still to draw
dmask   .word 0                 ; the parts to draw
dcol    .byte 0                 ; the colour dch writes
dnum    .word 0                 ; ddec's number
ddig    .fill 5                 ; ...its digits
dhdr    .fill 16                ; the disk's name (PETSCII, 0 after)
did     .fill 5                 ; its ID and DOS type

; the buffers: past the end of the program file (diskui.asm is included
; last), not loaded
        .virtual
dlbuf   .fill DLINE + 3         ; a listing line's text (3 zeros after)
dscr    .fill 16                ; dfrow: the name's screen codes
dmbuf   .fill 41                ; a row 24 message put together
dbtxt   .fill DMAX * 3          ; the blocks, 3 screen codes
dtype   .fill DMAX              ; 0 DEL, 1 SEQ, 2 PRG, 3 USR, 4 REL, 5 ?
dnames  .fill DMAX * 16         ; 0 after a name shorter than 16
dend
        .endv
        .cerror dend > $c000, "the disk code and buffers must stay below the screen"
