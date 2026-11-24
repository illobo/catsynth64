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
sname   .fill SNAMEL            ; the open slot's name (length 0: the style's)
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

; X = slot: the working copy (song, tweaks, sname) into it / out of it
; (slot_put / slot_fetch; a slot is laid out the same way, SLOTLEN bytes)
slot_put
        lda sltlo,x
        sta cd
        lda slthi,x
        sta cd+1
        #setw cs, song
        lda #SONGLEN
        jsr mcopy
        jsr cdnext
        #setw cs, tweaks
        lda #TWLEN
        jsr mcopy
        jsr cdtwk
        #setw cs, sname
        lda #SNAMEL
        jmp mcopy
cdnext  lda cd                  ; cd += SONGLEN
        clc
        adc #SONGLEN
        sta cd
        bcc +
        inc cd+1
+       rts
cdtwk   lda cd                  ; cd += TWLEN
        clc
        adc #TWLEN
        sta cd
        bcc +
        inc cd+1
+       rts

slot_fetch
        lda sltlo,x
        sta cs
        lda slthi,x
        sta cs+1
        #setw cd, song
        lda #SONGLEN
        jsr mcopy
        jsr csnext
        #setw cd, tweaks
        lda #TWLEN
        jsr mcopy
        lda cs
        clc
        adc #TWLEN
        sta cs
        bcc +
        inc cs+1
+       #setw cd, sname
        lda #SNAMEL
        jmp mcopy
csnext  lda cs
        clc
        adc #SONGLEN
        sta cs
        bcc +
        inc cs+1
+       rts                     ; (cs += SONGLEN)

; the ten styles' songs into the ten slots (the web edition: the ten
; techno songs); slot 1 open
slots_init
        jsr slots_defaults
        .if WEB
        jsr slots_techno
        .endif
        lda #0
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
        jsr seq_apply
        ; fall through
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
        bne +
        lda #0                  ; the open one: nothing to do (a switch
        sta pslot               ; or new sounds waiting are called off)
        sta pstyle
        rts
+       ldx running
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
        jmp message

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
        lda running
        bne +
        jsr sfx_stop
+       jmp slot_play

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
+       lda pslot
        beq +
        ldx #0
        stx pslot
        sec
        sbc #1
        jsr slot_switch
+       lda pstyle
        beq st9
        ldx #0
        stx pstyle
        sec
        sbc #1
        jmp style_apply
st9     rts

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
