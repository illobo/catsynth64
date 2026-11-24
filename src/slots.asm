; ------------------------------------------------------------------ song slots
; Ten songs in memory, on the keys 1-0: each slot a whole song (seq.asm's
; song block, its tweaks and a name). At start they hold the ten styles'
; songs. The song block (song, tweaks, sname) is the open slot's working
; copy: switching puts it back into its slot and fetches the other.
;
;   1-0            the slot (while playing: at the end of the bar, so the
;                  groove keeps going; stopped: at once)
;   SHIFT+1-0      the open slot's song with that style's sounds: its kit,
;                  bass instrument, root and scale; the bars, the tempo
;                  and the settings stay (also at the end of the bar)
;   row 24's name  left click: the next slot; right click: the style list
;                  (a page over the matrix, ui.asm's settings page code)
;   the disk page  Load / Save act on the open slot (it takes the file's
;                  name); New: this slot, all slots, or the ten defaults
;
; The slots live past the program (not loaded): see the .virtual block at
; the end of catsynth.asm.

NSLOTS  = 10
SNAMEL  = 17                    ; a name: length, 16 characters (PETSCII)
SLOTLEN = SONGLEN + TWLEN + SNAMEL

curslot .byte 0                 ; the open slot
pslot   .byte 0                 ; a slot to switch to (+1), 0 none
pstyle  .byte 0                 ; a style to give the song (+1), 0 none
spick   .byte 0                 ; the style list is up (with tweakon)
sli     .byte 0                 ; the loops' slot / style index
mcn     .byte 0                 ; mcopy: the byte count (pkdraw: a scratch)
cs      .word 0                 ; mcopy: from
cd      .word 0                 ; ...to

; each slot's address in slotmem (low bytes, high bytes), indexed by slot
sltlo   .for i = 0, i < NSLOTS, i += 1
        .byte <(slotmem + i * SLOTLEN)
        .next
slthi   .for i = 0, i < NSLOTS, i += 1
        .byte >(slotmem + i * SLOTLEN)
        .next

; copy A bytes (1-255) from cs to cd (the addresses patched into mc1 / mc2);
; cs and cd stay as they were
mcopy   sta mcn
        lda cs
        sta mc1+1
        lda cs+1
        sta mc1+2
        lda cd
        sta mc2+1
        lda cd+1
        sta mc2+2
        ldy #0
mc1     lda $ffff,y             ; (cs)
mc2     sta $ffff,y             ; (cd)
        iny
        cpy mcn
        bne mc1
        rts

; the 16-bit value into the word at dst
setw    .macro dst, value
        lda #<(\value)
        sta \dst
        lda #>(\value)
        sta \dst+1
        .endm

; X = slot: the working copy (song, tweaks, sname: SLOTLEN bytes in a row,
; as a slot is laid out) into it / out of it (slot_put / slot_fetch)
slot_put
        lda sltlo,x
        sta cd
        lda slthi,x
        sta cd+1
        #setw cs, song
        jmp scopy
slot_fetch
        lda sltlo,x
        sta cs
        lda slthi,x
        sta cs+1
        #setw cd, song
        ; fall through
; SLOTLEN bytes from cs to cd: two halves a pass (~11.5 cycles a byte, ~2.9k
; for a slot: the bar-line switch puts one back and fetches one in a frame)
SLOTH   = SLOTLEN / 2
        .cerror SLOTLEN != 2 * SLOTH, "SLOTLEN is even"
scopy   lda cs
        sta sc1+1
        lda cs+1
        sta sc1+2
        lda cd
        sta sc2+1
        lda cd+1
        sta sc2+2
        lda cs                  ; (the second half's addresses: + SLOTH)
        clc
        adc #SLOTH
        sta sc3+1
        lda cs+1
        adc #0
        sta sc3+2
        lda cd
        clc
        adc #SLOTH
        sta sc4+1
        lda cd+1
        adc #0
        sta sc4+2
        ldy #SLOTH-1
sc1     lda $ffff,y             ; (cs)
sc2     sta $ffff,y             ; (cd)
sc3     lda $ffff,y             ; (cs + SLOTH)
sc4     sta $ffff,y             ; (cd + SLOTH)
        dey
        bpl sc1
        rts

; unsaved changes: each slot keeps a checksum of its song as it was last
; loaded, saved or made (song and tweaks); Load asks when the open slot's
; differs (diskui.asm dload)
; ssum: the working copy's checksum -> sumlo / sumhi (Fletcher, 8 bits each)
ssum    lda #0
        sta sumlo
        sta sumhi
        ldx #0
-       lda song,x              ; song + tweaks: 229 bytes in a row
        clc
        adc sumlo
        sta sumlo
        adc sumhi
        sta sumhi
        inx
        cpx #SONGLEN + TWLEN
        bne -
        rts
; the open slot's song as made: its checksum kept (X = the slot: smark)
sclean  ldx curslot
smark   stx sli2
        jsr ssum
        ldx sli2
        lda sumlo
        sta slsumlo,x
        lda sumhi
        sta slsumhi,x
        rts
; Z clear when the open slot's song changed since then
sedited jsr ssum
        ldx curslot
        lda sumlo
        cmp slsumlo,x
        bne +
        lda sumhi
        cmp slsumhi,x
+       rts
sumlo   .byte 0
sumhi   .byte 0
sli2    .byte 0
slsumlo .fill NSLOTS
slsumhi .fill NSLOTS

; the ten styles' songs into the ten slots (the web edition: the ten
; techno songs); slot 1 open
slots_init
        pha                     ; A = the slot to open
        jsr slots_defaults
        pla
        .if WEB
        jsr slots_techno        ; (the techno songs: slot 1 open)
        lda #0
        .endif
        sta curslot
        tax
        jsr slot_fetch
        jmp slot_play

        .if WEB
; the web edition (no disk drive there): the ten techno songs, packed as on
; the disk (build/techno.inc), unpacked into the slots with their names
slots_techno
        ldx #0
-       stx sli
        lda tslo,x              ; song sli's packed bytes -> disk_buf
        sta cs
        lda tshi,x
        sta cs+1
        #setw cd, disk_buf
        lda tslen,x
        jsr mcopy
        ldx sli
        lda tslen,x
        jsr song_unpack
        bcs +                   ; (never: tools/techno.py checks them)
        lda sli                 ; the name: tsnames + 17 * slot
        asl a
        asl a
        asl a
        asl a
        adc sli
        tax
        ldy #0
-       lda tsnames,x
        sta sname,y
        inx
        iny
        cpy #SNAMEL
        bne -
        ldx sli
        jsr smark
        ldx sli
        jsr slot_put
+       ldx sli
        inx
        cpx #NSLOTS
        bne --
        rts
        .endif                  ; (the songs: ui.asm helpbuf)

; every slot back to its style's song (the working copy is overwritten)
slots_defaults
        ldx #0
-       stx sli
        jsr seq_load            ; X = style: its song, its settings
        lda #0
        sta sname
        ldx sli
        jsr smark
        ldx sli
        jsr slot_put
        ldx sli
        inx
        cpx #NSLOTS
        bne -
        rts

; the working copy: a new, empty song in its style (its tempo, sounds and
; settings as made; one bar, nothing on it)
slot_blank
        lda song                ; the style (song+0's low nibble)
        and #$0f
        tax
        jsr seq_load
        lda #0
        sta sname
        ldx #192                ; (192 bytes: X 192..1)
-       sta song+20,x           ; the patterns, song+21..+212, empty
        dex
        bne -
        sta song+5              ; the chain: bar A
        lda #1
        sta song+4              ; ...once
        rts

; the working copy plays: the style's harmony, from the top, the panel shown
slot_play
        lda song
        and #$0f
        tax
        lda harmtab,x
        sta harmony
        lda #0                  ; undo (live play): a snapshot of this song,
        sta undook              ; taken now if REC is on, or none
        lda rec
        beq +
        jsr usnap
+       jsr seq_apply
        lda slbar               ; on the bar line (slots_tick): the panel
        beq songshow            ; the next frame (infos), the music first
        lda #1
        sta showp
        rts
; after a new song: the bar being edited A, the view, the whole panel
songshow
        lda #0
        sta eslot
        jsr setep
        jsr findchain
        jsr ui_rescale
        jsr autoview
        lda #$ff                ; no step / bar drawn yet: all redrawn
        sta lstep
        sta lbar
        lda #$80                ; the info and song line too
        sta dirty
        jmp status

; A = slot: open it (playing: at the end of the bar)
slot_select
        cmp curslot
        bne sls2
        lda pslot               ; the open one: nothing to do (a switch
        ora pstyle              ; or new sounds waiting are called off,
        beq +                   ; and said so)
        lda #0
        sta pslot
        sta pstyle
        ldx #<msg_off
        ldy #>msg_off
        jmp message
+       rts
sls2    ldx #0                  ; (new sounds asked for the open slot: off,
        stx pstyle              ; not given to the next one)
        ldx running
        bne +
        jmp slot_switch         ; stopped: at once
+       clc
        adc #1
        sta pslot               ; (slot + 1: slots_tick does it)
        sec
        sbc #1
        jsr slnum               ; "Next bar: slot N"
        ldx #<msg_nslot
        ldy #>msg_nslot
        jsr message
        lda #250                ; (shown until the switch: a bar is at most
        sta msgt                ; 240 frames; status clears it then)
        rts

; A = slot: now (the open one put back first, so its edits stay)
slot_switch
        pha
        ldx curslot
        jsr slot_put
        pla
        sta curslot
        tax
        jsr slot_fetch
        lda running
        bne +
        jsr sfx_stop            ; stopped: the old song's notes cut
+       jmp slot_play

; A = style: the open song with its sounds (playing: at the end of the bar)
style_select
        ldx running
        bne +
        jmp style_apply
+       clc
        adc #1
        sta pstyle              ; (style + 1)
        ldx #<msg_nstyle
        ldy #>msg_nstyle
        jmp message

; A = style: now; song+0's low nibble (the mode, the high nibble, stays)
style_apply
        sta sli
        lda song
        and #$f0
        ora sli
        sta song
        and #$f0                ; in mode Own the bass plays its notes as
        bne +                   ; they are: each one off the new style's
        jsr bsnap               ; scale moves to the nearest note in it
+       lda running
        bne +
        jsr sfx_stop
+       jmp slot_play

; the bass notes of all four bars into the scale of style sli (its bass
; scale, inscl / insch): a note off it moves to the nearest one in it (down
; first), its length and slide kept. ~3000 cycles.
bsnap   ldx sli
        lda inscl,x
        sta smask
        lda insch,x
        sta smask+1
        ldy #3*48+31            ; the bass rows: 16-31 of each bar's 48
bsn1    lda bsrow,y             ; (not a bass step: skipped)
        beq bsn9
        lda song+21,y
        and #$1f
        beq bsn9
        sta bsnote
        ldx #0                  ; tries: 0, -1, +1, -2, +2 ...
bsn2    lda bsnote
        clc
        adc bsoff,x
        beq bsn3                ; (past the ends: the next try)
        cmp #32
        bcs bsn3
        sta tmp2
        sty bsy
        stx bsx
        jsr inscale             ; (changes X)
        php
        ldy bsy
        ldx bsx
        plp
        bne bsn4
bsn3    inx
        cpx #len(BSOFF)
        bne bsn2
        beq bsn9                ; (none near: as it was)
bsn4    lda song+21,y
        and #$e0
        ora tmp2
        sta song+21,y
bsn9    dey
        cpy #$ff
        bne bsn1
        rts
bsrow   .for i = 0, i < 3*48+32, i += 1
        .byte (i % 48) >= 16 && (i % 48) < 32
        .next
BSOFF   = [0, -1, 1, -2, 2, -3, 3]
bsoff   .char BSOFF
bsnote  .byte 0
bsy     .byte 0
bsx     .byte 0

; once a frame after the music: a switch waiting, done on the bar line (the
; next tick starts step 0: seq_apply restarts the song there, on time)
slots_tick
        lda pslot
        ora pstyle
        beq st9
        lda diskon              ; (not under the disk page or the help:
        ora helpon              ; they cover the panel)
        bne st9
        lda running             ; stopped: now
        beq +
        lda step                ; playing: the last frame of the bar (step
        cmp #15                 ; 15, 1 frame left)
        bne st9
        lda stepcnt
        cmp #1
        bne st9
+       inc slbar               ; (slot_play: the panel a frame later)
        lda pslot
        beq +
        ldx #0
        stx pslot
        sec
        sbc #1
        jsr slot_switch
+       lda pstyle
        beq +
        ldx #0
        stx pstyle
        sec
        sbc #1
        jsr style_apply
+       lda #0
        sta slbar
st9     rts
slbar   .byte 0                 ; 1 while slots_tick switches
showp   .byte 0                 ; 1: songshow still to come (infos)
rescp   .byte 0                 ; 1: M's ui_rescale and status to come (infos)

; A = slot 0-9: its key ("1"-"9", "0") into the slot message
slnum   clc
        adc #1
        cmp #10
        bcc +
        lda #0
+       ora #$30                ; the digit's screen code
        sta msg_nslotn
        rts

; ------------------------------------------------------------------ the list
; the style list: a page over the matrix (ui.asm's settings page, with
; spick): two columns of five, a click (or a key 1-0) gives the open song
; that style's sounds
pick_open
        jsr tweak_open
        lda #1
        sta spick
        rts

; where style n's entry goes (its key, then its name 2 columns on)
pkrow   .byte 2, 3, 4, 5, 6, 2, 3, 4, 5, 6      ; rows 17-21 (MROW + n)
pkcol   .byte 3, 3, 3, 3, 3, 21, 21, 21, 21, 21

; the list drawn: per style its key (yellow) and its name (from ui.asm's
; settings page code, when the page is drawn)
pkdraw  lda #0
        sta sli
-       ldx sli
        lda pkrow,x
        jsr rowptr
        ldx sli
        ldy pkcol,x
        txa                     ; the key: 1-9, 0
        clc
        adc #1
        cmp #10
        bcc +
        lda #0
+       ora #$30
        sta (gp),y
        lda #C_YEL
        sta (cp),y
        iny
        iny
        lda #C_LGR              ; the open song's style white, the rest grey
        ldx sli
        cpx cstyle
        bne +
        lda #C_WHT
+       sta pkcolr
        lda sli                 ; the name: 9 characters, the first upper case
        asl a                   ; (stynames + 10 * style)
        sta mcn
        asl a
        asl a
        adc mcn
        tax
        lda #9
        sta mcn
        lda #$40
        sta pkup
-       lda stynames,x
        cmp #27                 ; a letter (screen code 1-26): + $40 is its
        bcs +                   ; upper case
        ora pkup
+       sta (gp),y
        lda #0
        sta pkup
        lda pkcolr
        sta (cp),y
        inx
        iny
        dec mcn
        bne -
        inc sli
        lda sli
        cmp #NSTYLES
        bne --
        rts
pkup    .byte 0                 ; $40 for the name's first letter, then 0
pkcolr  .byte 0                 ; the name's colour

; a click on the list: Y = row; ccol (the column). On a style: that style
; (style_select); anywhere else: the list closes
pkclick cpy #MROW+2
        bcc pk8
        cpy #MROW+7
        bcs pk8
        tya
        sec
        sbc #MROW+2
        ldx ccol
        cpx #20                 ; the right column: keys 6-0 (+5)
        bcc +
        adc #4                  ; (C set: +5)
+       pha
        jsr tweak_close
        pla
        jmp style_select
pk8     jmp tweak_close
