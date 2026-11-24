; ------------------------------------------------------------------ disk
; Songs on disk: pack/unpack the song block and KERNAL SAVE / OPEN+CHRIN
; to device 8, any file name (PRG, one or two blocks; the slot routines use
; "CATSONG0".."CATSONG9"). The disk page (diskui.asm) reads the directory
; with dk_enter / dk_status / dk_leave too.
; The includer defines `song` (the 213-byte block below), `tweaks` (the
; 16-byte sound settings outside the song block, seq.asm: twbend[4],
; twvowel[4], twtone[4] 0-16 (8 = as made), twside (bass Level << 4 0-8 |
; Sidechain 0-8), twtune (0-16, 8 = as made), btweak (Delay << 4 0-7 | Wave
; 0-3), tflags (bits 0-2 Meowize, Res boost, Dub filter; Cat Size << 4 0-3))
; and NSTYLES.
;
; The song block (seq.asm):
;   song+0 style  +1 tempo  +2 swing  +3 esteps  +4 chainlen  +5 chain[16]
;   song+21 pats: slot s, cat c (0 drums, 1 bass, 2 singer) at +21+s*48+c*16
;
; The packed form (tools/songpack.py is the reference), 64 to 256 bytes:
;   "CS" ($43 $53), version 5, the 21 header bytes as they are, the 16
;   tweak bytes as they are, then for each of the 12 rows (s0 drums, s0
;   bass, s0 singer, s1 drums, ...) a 16-bit step mask (bit n: step n is
;   not 0; low byte first) followed by the non-zero step bytes in step
;   order. An empty row is 2 zero bytes.
;   A version 5 file with Bend, Vowel, Tone or Tune over 16, Sidechain or
;   the bass Level over 8, btweak's high nibble over 7 or low over 3, or bad
;   tflags bits (3, 6, 7) is bad.
;   Version 4 had 9 tweak bytes (packed: 4 x Bend << 4 | Vowel, Tone0 << 4
;   | Tone1, Tone2 << 4 | Tone3, dtweak (Sidechain << 4 | Tune, 0-7 each,
;   Tune 4 as made, 1/8 steps), btweak, tflags): the nibbles load as they
;   are but 15 -> 16 (the 0-15 scale's top is 16 now), Sidechain as it is,
;   Tune t -> 8 + 2 * (t - 4); dtweak nibbles over 7, a bad btweak or
;   tflags make it bad.
;   Version 3 had 4 tweak bytes (the old mtweak: per meow kind Bend << 4 |
;   Vowel, 0-7 each, factor n/4): they load as the 0-16 Bend and Vowel with
;   the same factor (dk_v3map: 0 2 4 6 8 9 10 11), the rest as made; a
;   nibble over 7 there is bad. Version 1 and 2 files have no tweak bytes:
;   all as made (dk_twdef: 8 x12, Sidechain 0, Tune 8, btweak 0, tflags 0).
;   Version 2: a drum step byte is a drum role 1..14 (seq.asm; each style
;   maps the roles to its own sounds). Version 1 (before the roles): it was
;   one of 17 global kit sounds; song_unpack still takes version 1 files
;   and turns their drum steps (rows s*3+0) into roles with dk_kitv1
;   (build/kitv1.inc, from tools/styles.py: kick 1 -> BD, snare 2 -> SN,
;   hat 3 -> CH, ohat 4 -> OH, drop 5 -> DR, skank 6 -> SK, rim 7 -> RS,
;   shk 8 -> SH, s06 ohat 9 -> OH, s06 kclap 10 -> CP, ghost 11 -> GH,
;   boom 12 -> BM, bap 13 -> BP, dust 14 -> DU, s09 kclap 15 -> CP,
;   s09 open 16 -> OH, ride 17 -> RD); other values become 0.
; The file is the packed form with its PRG load address (that of
; disk_buf, not used: LOAD relocates): at most 258 bytes, so a song with
; more than 252 packed bytes (nearly every step set) takes 2 blocks.
; Lengths are a byte: 0 stands for 256 (the shortest file is 48 bytes).

; Routines (none uses zero page; all clobber A, X, Y):
;   song_pack     song, tweaks -> disk_buf. Out: A = disk_len = the length
;                 (0: 256).
;   song_unpack   disk_buf (A = its length, 0: 256) -> song, tweaks.
;                 Checks the magic, the version (1-5; 1-4 converted, above), the
;                 ranges (style < NSTYLES, tempo 4..15, swing < tempo, song+3
;                 any (echo | transpose), chainlen 1..16, chain < 4, the
;                 tweak bytes, above) and that the masks use exactly A bytes.
;                 Out: C = 1 bad, song and tweaks untouched (unpacked to a
;                 scratch area first).
;                 Drum step bytes must be roles 0..NKIT (bass and singer
;                 bytes are any value: every one plays something).
;   disk_setname  X/Y = a name (PETSCII), A = its length (1-16): the file
;                 disk_saven, disk_loadn and disk_scratch use.
;   disk_saven    song_pack, SAVE it as "CS64 TMP"; only when that went
;                 well, scratch "S0:name" and rename the new file to name
;                 ("R0:name=CS64 TMP"): a failed save (disk full...) leaves
;                 the old file as it was. The drive's status read each time.
;   disk_savenew  song_pack, SAVE under the name: with a file there already
;                 (the drive's 63) C = 1, A = DE_EXISTS, nothing changed.
;   disk_loadn    OPEN name (secondary 0) and CHRIN into disk_buf, at most
;                 DK_PACKMAX bytes after the load address (a longer file is
;                 a bad file, read no further: nothing past disk_buf is
;                 written), read the drive's status, song_unpack. The song
;                 changes only when all went well.
;   disk_scratch  "S0:name" (01 FILES SCRATCHED, also when there was none).
;   disk_save, disk_load   A = slot 0-9: the name "CATSONGn", then as above.
;   All: out C = 0 ok; C = 1 error, A = disk_err:
;       1-9   the KERNAL's error (4 file not found (also the drive's 62),
;             5 device not present...)
;       $10   bad file (not a song, or too long)
;       $11   drive error: disk_dos holds its code (26 write protect,
;             72 disk full...)
;       $12   disk_savenew: the file is there already
;     disk_st = the KERNAL status ($90) after the SAVE / LOAD,
;     disk_dos = the drive's status code (binary, 0 = ok),
;     disk_bank = $dd00 as the KERNAL left it (bits 0-1: the VIC bank,
;     before disk.asm puts the caller's bank back).
;
; Around the KERNAL calls (dk_enter / dk_leave): zero page $02-$ff is
; saved to dk_zp and put back, $00/$01 set to $2f/$36 and put back, the
; screen blanked ($d011 bit 4) and the sprites off ($d015) so badlines and
; sprite DMA cannot upset the serial timing, then both put back; $dd00
; bits 0-1 (VIC bank) and $dd02 put back. The KERNAL zero page the serial
; code relies on is set to its idle state: $90 = 0, $91 = $ff (STOP key not
; down), $94 = $a3 = 0 (no deferred byte, no EOI), $98 = 0 (no open
; files), $99 = 0, $9a = 3, $9d = 0 (no messages). Called and returned with
; interrupts off; the KERNAL's serial code does CLI, which is harmless
; while the CIA and VIC interrupt masks are off, as in the main program.
; The KERNAL vectors $031a-$0333 are used as they are (not reset, so a
; speeder cartridge still works): the caller must not have changed them.
; Page 2 KERNAL tables ($0259-$0276 file tables) are written.
;
; Memory: ~1200 bytes of code and variables (with dk_kitv1); disk_buf 256
; bytes, dk_zp 254 (also the unpack scratch area, song + tweaks, 229): ~1700
; bytes in all. Define DISK_BUF before the include to put the 510 bytes of buffers
; there instead of in the program (not in $c000-$cfff, nor under the ROMs).
; Symbols: song_pack, song_unpack, disk_save, disk_load, disk_saven,
; disk_loadn, disk_scratch, disk_setname, disk_buf,
; disk_len, disk_err, disk_st, disk_dos, disk_bank, DE_*, DK_*, dk_*, K_*.

DK_SONGLEN  = 213               ; the song block: the header, 192 step bytes
DK_HDR  = 21                    ; song+0..+20 (style ... chain[16])
DK_TWLEN = 16                   ; `tweaks` in memory
DK_TW   = DK_TWLEN              ; ...in the file (version 5, raw)
DK_TW4  = 9                     ; the tweak bytes of version 4
DK_TW3  = 4                     ; ...of version 3
DK_TWPOS = 3 + DK_HDR           ; the tweak bytes start here (v3-v5)
DK_ROWS = DK_TWPOS + DK_TW      ; the rows start here (v5; v4: 7 less, v3: 12, v1/v2: 16)
DK_PACKMAX  = DK_ROWS + 12*18  ; 256 (a length byte of 0 means 256)
DK_MINLEN = 3 + DK_HDR + 24     ; the shortest file (v1/v2, 12 empty rows)
DISK_DEV = 8

DE_BADFILE = $10                ; disk_err: not a song (or too long)
DE_DRIVE   = $11                ; ...the drive said no (disk_dos)
DE_EXISTS  = $12                ; ...disk_savenew: a file of that name is there

; the KERNAL's jump table
K_SETLFS = $ffba                ; A = file no., X = device, Y = secondary
K_SETNAM = $ffbd                ; A = name length, X/Y = its address
K_OPEN   = $ffc0                ; C set: error, A = its number
K_CLOSE  = $ffc3                ; A = file no.
K_CHKIN  = $ffc6                ; X = file no.: CHRIN reads from it
K_CLRCHN = $ffcc                ; back to the keyboard / screen
K_CHRIN  = $ffcf                ; A = the next byte; $90 says how it went
K_SAVE   = $ffd8                ; A = zp pointer to the start, X/Y = end + 1

DK_PTR   = $fb                  ; SAVE's start pointer (only while in the KERNAL)

; ------------------------------------------------------------------ pack
; song, tweaks -> disk_buf (the packed form above). Out: A = disk_len
song_pack
        ldx #2                  ; "CS", the version
-       lda dk_magic,x
        sta disk_buf,x
        dex
        bpl -
        ldx #DK_HDR-1           ; the header as it is
-       lda song,x
        sta disk_buf+3,x
        dex
        bpl -
        ldx #DK_TWLEN-1         ; the tweaks as they are
-       lda tweaks,x
        sta disk_buf+DK_TWPOS,x
        dex
        bpl -
        ldy #DK_ROWS            ; Y: out
        ldx #0                  ; X: step of the 192
pk_row  sty dk_mpos             ; the mask goes here
        iny
        iny
pk_step lda song+DK_HDR,x
        beq +
        sta disk_buf,y
        iny
+       cmp #1                  ; C = not empty: into the mask from the top,
        ror dk_mhi              ; so step 0 ends in bit 0
        ror dk_mlo
        inx
        txa
        and #15
        bne pk_step             ; (16 steps a row)
        sty dk_t                ; the row's mask into its place
        ldy dk_mpos
        lda dk_mlo
        sta disk_buf,y
        lda dk_mhi
        sta disk_buf+1,y
        ldy dk_t
        cpx #192
        bne pk_row
        sty disk_len            ; (256 bytes at most: Y wraps to 0)
        tya
        rts

; ------------------------------------------------------------------ unpack
; disk_buf (A = its length, 0: 256) -> song, tweaks; C set: bad (see above)
up_bad0 sec
        rts
song_unpack
        sta disk_len            ; (0: 256)
        tax
        beq +
        cmp #DK_MINLEN
        bcc up_bad0
+       ldx #1
-       lda disk_buf,x          ; "CS"
        cmp dk_magic,x
        bne up_bad0
        dex
        bpl -
        lda disk_buf+2          ; version 1-5
        beq up_bad0
        cmp #6
        bcs up_bad0
        lda disk_buf+3          ; style (low nibble; high: the mode, 0-7)
        and #$0f
        cmp #NSTYLES
        bcs up_bad0
        lda disk_buf+3          ; (the mode: bit 7 clear)
        cmp #$80
        bcs up_bad0
        lda disk_buf+4          ; tempo 4..15
        cmp #4
        bcc up_bad0
        cmp #16
        bcs up_bad0
        lda disk_buf+5          ; swing < tempo (low nibble; high: the bass
        and #$0f                ; transpose, any)
        cmp disk_buf+4
        bcs up_bad0
                                ; song+3: echo steps (low nibble) and the
                                ; singer's transpose (high): any value
        lda disk_buf+7          ; chainlen 1..16
        beq up_bad0
        cmp #17
        bcs up_bad0
        ldx #15
-       lda disk_buf+8,x        ; chain: slots 0..3
        cmp #4
        bcs up_bad0
        sta dk_tmp+5,x
        dex
        bpl -
        ldx #4                  ; song+0..+4 (chain[] went above)
-       lda disk_buf+3,x
        sta dk_tmp,x
        dex
        bpl -
        jsr up_tw               ; the tweaks -> dk_tmp+DK_SONGLEN, X: in
        bcc up_rows
up_bad2 sec                     ; (bad: from up_tw with C set, or cut short
        rts                     ; at a row's mask, with C clear)
up_rows stx dk_t                ; dk_rem: the row bytes (the length - X;
        lda disk_len            ; X never passes 255 while there are some)
        sec
        sbc dk_t
        sta dk_rem
        ldy #0                  ; Y: step of the 192, X: in
up_row  lda dk_rem              ; the mask must be inside
        cmp #2
        bcc up_bad2
        sbc #2
        sta dk_rem
        lda disk_buf,x
        sta dk_mlo
        lda disk_buf+1,x
        sta dk_mhi
        inx
        inx
up_step lsr dk_mhi              ; C = step's bit, step 0 first
        ror dk_mlo
        lda #0
        bcc +
        lda dk_rem
        beq up_bad              ; its byte is missing
        dec dk_rem
        lda disk_buf,x
        inx
+       sta dk_tmp+DK_HDR,y
        iny
        tya
        and #15
        bne up_step
        cpy #192
        bne up_row
        lda dk_rem              ; all used
        bne up_bad
        lda disk_buf+2          ; version 1: drum sounds -> drum roles
        cmp #1
        beq up_v1
        ldx #DK_HDR             ; 2-5: the drum rows hold roles 0..NKIT; a
up_ckrow                        ; bigger byte (a damaged or hand-made file)
        ldy #16                 ; would send the player into data: refused
-       lda dk_tmp,x
        cmp #NKIT+1
        bcs up_bad
        inx
        dey
        bne -
        txa                     ; past the bass and singer rows
        clc
        adc #32
        tax
        cpx #DK_HDR+192
        bcc up_ckrow
        bcs up_copy
up_v1
        ldx #DK_HDR             ; X: slot s's drum row, s*48 on
up_cvrow
        lda #16                 ; dk_t: the row's 16 steps
        sta dk_t
up_cv   ldy dk_tmp,x
        lda #0
        cpy #18                 ; 1..17 -> dk_kitv1, others 0
        bcs +
        tya
        beq +
        lda dk_kitv1-1,y
+       sta dk_tmp,x
        inx
        dec dk_t
        bne up_cv
        txa                     ; past the bass and singer rows
        clc
        adc #32
        tax
        cpx #DK_HDR+192
        bcc up_cvrow
up_copy ldx #0                  ; all good: the scratch copy is the song
-       lda dk_tmp,x
        sta song,x
        inx
        cpx #DK_SONGLEN
        bne -
        ldx #DK_TWLEN-1
-       lda dk_tmp+DK_SONGLEN,x
        sta tweaks,x
        dex
        bpl -
        clc
        rts
up_bad  sec
        rts

; the file's tweaks into dk_tmp+DK_SONGLEN (v1/v2: as made, v3, v4:
; converted, v5: as they are). Out: C = 1 bad; else X = where the rows start.
up_tw   ldx #DK_TWLEN-1         ; as made, then the file's
-       lda dk_twdef,x
        sta dk_tmp+DK_SONGLEN,x
        dex
        bpl -
        ldx #3+DK_HDR           ; X: in (v1/v2: no tweak bytes)
        lda disk_buf+2          ; the version
        cmp #3
        bcc up_twok
        bne up_v45
up_v3   ldx #DK_TW3-1           ; v3: Bend << 4 | Vowel, 0-7 (factor n/4)
-       lda disk_buf+DK_TWPOS,x ; -> 0-16 (dk_v3map)
        and #$88                ; (a nibble over 7)
        bne up_bad1
        lda disk_buf+DK_TWPOS,x
        lsr a
        lsr a
        lsr a
        lsr a
        tay
        lda dk_v3map,y
        sta dk_tmp+DK_SONGLEN,x
        lda disk_buf+DK_TWPOS,x
        and #7
        tay
        lda dk_v3map,y
        sta dk_tmp+DK_SONGLEN+4,x
        dex
        bpl -
        ldx #DK_TWPOS+DK_TW3    ; X: in
up_twok clc
        rts
up_bad1 sec
        rts
up_v45  cmp #4
        beq up_v4
        ldx #13                 ; v5: Bend, Vowel, Tone, Sidechain, Tune
-       lda disk_buf+DK_TWPOS,x ; under their limits
        cmp dk_twlim,x
        bcs up_bad1
        sta dk_tmp+DK_SONGLEN,x
        dex
        bpl -
        lda disk_buf+DK_TWPOS+14 ; btweak: Delay 0-7, Wave 0-3
        and #$8c
        bne up_bad1
        lda disk_buf+DK_TWPOS+15 ; tflags: bits 0-2 (Meowize, Res boost,
        and #$08                ; Dub filter), bits 4-5 the Cat Size 0-3
        bne up_bad1
        lda disk_buf+DK_TWPOS+15 ; (bits 6-7 clear)
        cmp #$40
        bcs up_bad1
        lda disk_buf+DK_TWPOS+12 ; twside: Sidechain 0-8, the bass's Level 0-8
        cmp #$90                ; (the Level, high nibble; dk_twlim let it be)
        bcs up_bad1
        and #$0f
        cmp #9
        bcs up_bad1
        lda disk_buf+DK_TWPOS+14
        sta dk_tmp+DK_SONGLEN+14
        lda disk_buf+DK_TWPOS+15
        sta dk_tmp+DK_SONGLEN+15
        ldx #DK_ROWS            ; X: in
        clc
        rts
up_v4   lda disk_buf+DK_TWPOS+6 ; v4: dtweak nibbles 0-7
        and #$88
        bne up_bad1
        lda disk_buf+DK_TWPOS+7 ; btweak 0-7, 0-3
        and #$8c
        bne up_bad1
        lda disk_buf+DK_TWPOS+8 ; tflags: bit 0
        and #$fe
        bne up_bad1
        ldx #3                  ; Bend << 4 | Vowel (0-15, 15 -> 16)
-       lda disk_buf+DK_TWPOS,x
        lsr a
        lsr a
        lsr a
        lsr a
        jsr up_15
        sta dk_tmp+DK_SONGLEN,x
        lda disk_buf+DK_TWPOS,x
        and #15
        jsr up_15
        sta dk_tmp+DK_SONGLEN+4,x
        dex
        bpl -
        ldx #2                  ; the Tones, two a byte (X: 2, 0)
        ldy #1
-       lda disk_buf+DK_TWPOS+4,y
        lsr a
        lsr a
        lsr a
        lsr a
        jsr up_15
        sta dk_tmp+DK_SONGLEN+8,x
        lda disk_buf+DK_TWPOS+4,y
        and #15
        jsr up_15
        sta dk_tmp+DK_SONGLEN+9,x
        dex
        dex
        dey
        bpl -
        lda disk_buf+DK_TWPOS+6 ; dtweak: Sidechain << 4 (0-7, as it is)
        lsr a
        lsr a
        lsr a
        lsr a
        sta dk_tmp+DK_SONGLEN+12
        lda disk_buf+DK_TWPOS+6 ; ...| Tune t (0-7, 4 as made, 1/8 steps)
        and #7                  ; -> 8 + 2 * (t - 4) = 2t (1/16 steps)
        asl a
        sta dk_tmp+DK_SONGLEN+13
        lda disk_buf+DK_TWPOS+7 ; btweak, tflags as they are
        sta dk_tmp+DK_SONGLEN+14
        lda disk_buf+DK_TWPOS+8
        sta dk_tmp+DK_SONGLEN+15
        ldx #DK_TWPOS+DK_TW4    ; X: in
        clc
        rts
up_15   cmp #15                 ; v4's 0-15 scale -> 0-16: 15 is 16 now
        bne +
        lda #16
+       rts
; ------------------------------------------------------------------ save
; disk_save: A = slot ("CATSONGn"); disk_saven: the name set (disk_setname).
; Out: C, A = disk_err (see above)
disk_save
        jsr dk_slot
disk_saven
        lda #1                  ; (replace: by way of a temporary file)
        .byte $2c               ; (bit abs: skips the lda below)
disk_savenew
        lda #0                  ; (new: a file there already is not touched)
        sta dk_repl
        jsr dk_clr
        jsr song_pack
        jsr dk_enter
        lda dk_repl
        bne dsv_rep
        jsr dk_setname          ; new: SAVE under the name; the drive says
        jsr dk_save             ; 63 FILE EXISTS if there is one, and
        bcs dsv_k             ; leaves it as it was
        lda disk_dos
        cmp #63
        bne +
        lda #DE_EXISTS
        bne dsv_k
+       cmp #20                 ; 00 ok (0x: messages), 20 up: errors
        bcs dsv_d
        jmp dk_ok
dsv_k   jmp dk_kerr             ; (the common exits, in reach)
dsv_d   jmp dk_drverr
dsv_rep lda #len(DK_TMPN)+3     ; replace: the new song saved as the
        ldx #<dk_scrtmp         ; temporary file first ("S0:" it, from an
        ldy #>dk_scrtmp         ; earlier failure)...
        jsr dk_send
        bcs dsv_k
        lda #len(DK_TMPN)
        ldx #<dk_scrtmp+3
        ldy #>dk_scrtmp+3
        jsr K_SETNAM
        jsr dk_save
        bcs dsv_bad
        lda disk_dos
        cmp #20
        bcs dsv_bdd
        jsr dk_scratch          ; ...only then the old one scratched,
        bcs dsv_k
        ldx dk_nlen             ; ...and the temporary file renamed:
        lda #"="                ; "R0:name=CS64 TMP"
        sta dk_ren+3,x
-       lda dk_cmd+2,x          ; (the name, at dk_ren+3)
        sta dk_ren+2,x
        dex
        bne -
        ldx #len(DK_TMPN)-1
        ldy dk_nlen
-       lda dk_scrtmp+3,x
        sta dk_ren+4+len(DK_TMPN)-1,y
        dey
        dex
        bpl -
        lda dk_nlen
        clc
        adc #4+len(DK_TMPN)
        ldx #<dk_ren
        ldy #>dk_ren
        jsr dk_send
        bcs dsv_k
        lda disk_dos
        cmp #20
        bcs dsv_d
        jmp dk_ok
dsv_bdd lda #DE_DRIVE           ; the save failed (disk full...): the
dsv_bad sta disk_err            ; temporary file goes, the old one is
        lda disk_dos            ; still there
        pha
        lda #len(DK_TMPN)+3
        ldx #<dk_scrtmp
        ldy #>dk_scrtmp
        jsr dk_send
        pla
        sta disk_dos
        lda disk_err
        cmp #DE_DRIVE
        beq dsv_d
        jmp dk_kerr

; SAVE disk_buf (disk_len bytes) as the file SETNAM named, then the drive's
; status (disk_dos). C = 1, A = KERNAL error.
dk_save lda #1                  ; file 1, drive 8, secondary 0 (SAVE: the
        ldx #DISK_DEV           ; start address goes first)
        ldy #0
        jsr K_SETLFS
        lda #<disk_buf
        sta DK_PTR
        lda #>disk_buf
        sta DK_PTR+1
        ldy #>disk_buf          ; end + 1 (disk_len 0: 256 bytes)
        lda disk_len
        bne +
        iny
+       clc
        adc #<disk_buf
        tax
        bcc +
        iny
+
        lda #DK_PTR
        jsr K_SAVE
        ldx $90                 ; ST
        stx disk_st
        bcs dks9
        txa
        bmi dks_np              ; (bit 7: device not present)
        jmp dk_status
dks_np  lda #5
        sec
dks9    rts

        .enc "none"
DK_TMPN = "cs64 tmp"            ; (64tass's "none": ASCII lower case becomes
dk_scrtmp .text "s0:", DK_TMPN   ; PETSCII $41-$5a, the drive's capitals)
dk_ren  .text "r0:"             ; "R0:name=CS64 TMP"
        .fill 1 + 16 + len(DK_TMPN)
dk_repl .byte 0

; "S0:name" on the command channel, then the drive's status (01 files
; scratched, also when there was none). C = 1, A = KERNAL error.
dk_scratch
        lda dk_nlen             ; "S0:" + the name: the command, sent as the
        clc                     ; command channel's file name by OPEN
        adc #3
        ldx #<dk_cmd
        ldy #>dk_cmd
; A, X/Y = a command: sent on the command channel, then the drive's status
dk_send jsr K_SETNAM
        jsr dk_lfs15
        jsr K_OPEN
        bcs +
        lda #15
        jsr K_CLOSE
        lda $90
        bmi dk_scnp             ; (device not present)
        jmp dk_status           ; "01, FILES SCRATCHED"
dk_scnp lda #5
        sec
+       rts

; delete the file named (disk_setname). Out: C, A = disk_err
disk_scratch
        jsr dk_clr
        jsr dk_enter
        inc dk_wantn            ; (how many went: the status's number)
        jsr dk_scratch
        dec dk_wantn
        bcs dk_kerr
        lda disk_dos
        cmp #20                 ; (01 files scratched is fine)
        bcs dk_drverr
        lda disk_cnt            ; ...but 0 files scratched: none matched
        bne +
        lda #4                  ; (file not found)
        bne dk_kerr
+       jmp dk_ok

; the common exits (also from diskui.asm's dir_read): dk_leave, then
; disk_err and C set as the routines above say
dk_kerr sta disk_err            ; A = KERNAL error
        jsr dk_leave
        lda disk_err
        sec
        rts
dk_dnp  lda #5                  ; device not present
        bne dk_kerr
dk_drverr
        lda disk_dos            ; 62 file not found: the KERNAL's error 4
        cmp #62
        bne +
        lda #4
        bne dk_kerr
+       lda #DE_DRIVE
        bne dk_kerr
dk_ok   lda #0
        sta disk_err
        jsr dk_leave
        lda #0
        clc
        rts

; ------------------------------------------------------------------ load
; Not the KERNAL's LOAD: OPEN (secondary 0, the LOAD channel) and CHRIN, at
; most DK_PACKMAX bytes after the load address, so a foreign file of that
; name cannot overwrite what follows disk_buf (a longer one is a bad file).
; disk_load: A = slot ("CATSONGn"); disk_loadn: the name set. Out: C, A =
; disk_err; the song and tweaks changed only on C clear
disk_load
        jsr dk_slot
disk_loadn
        jsr dk_clr
        jsr dk_enter
        jsr dk_setname
        lda #2                  ; file 2, drive 8, secondary 0
        ldx #DISK_DEV
        ldy #0
        jsr K_SETLFS
        jsr K_OPEN
        bcs dk_kerr
        lda $90
        bpl +                   ; (bit 7: device not present)
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
+       ldy #0                  ; Y: bytes read (dk_full: 256)
        sty dk_long
        sty dk_full
        jsr K_CHRIN             ; the load address (not used)
        jsr K_CHRIN
        lda $90
        sta disk_st
        bne dk_lclose           ; (already the end, or an error)
-       jsr K_CHRIN
        ldx $90                 ; ST: bit 6 the last byte, others errors
        stx disk_st
        ldx dk_full
        beq +
        inc dk_long             ; one too many: not a song
        bne dk_lclose
+       sta disk_buf,y
        iny
        bne +
        inc dk_full             ; (DK_PACKMAX = 256)
+       lda disk_st
        beq -                   ; more
dk_lclose
        sty dk_end
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
        bcs dk_lderr
        lda dk_long             ; (too long: a bad file, whatever ST says)
        bne +
        lda disk_st             ; serial errors other than EOF
        and #$bf
        beq +
dk_lderr
        jmp dk_drverr
+       jsr dk_leave
        lda dk_long
        bne dk_badfile
        lda dk_end              ; the length, 1..DK_PACKMAX (0: 256)
        bne +
        lda dk_full
        beq dk_badfile          ; (empty)
        lda dk_end
+       jsr song_unpack
        bcs dk_badfile
        lda #0
        sta disk_err
        rts
dk_badfile
        lda #DE_BADFILE
        sta disk_err
        sec
        rts

; ------------------------------------------------------------------ helpers
dk_slot and #15                 ; A = slot: "CATSONGn"
        ora #"0"
        sta dk_cmd+10
        ldx #6
-       lda dk_catsong,x
        sta dk_cmd+3,x
        dex
        bpl -
        lda #8
        sta dk_nlen
        rts

; disk_dos, disk_st cleared (no answer yet)
dk_clr  lda #0
        sta disk_dos
        sta disk_st
        rts

; X/Y = a file name (PETSCII), A = its length (1-16): the name for
; disk_saven, disk_loadn and disk_scratch
disk_setname
        stx dk_snl+1            ; (the address patched into dk_snl)
        sty dk_snl+2
        cmp #17                 ; at most 16
        bcc +
        lda #16
+       sta dk_nlen
        tax
        dex
dk_snl  lda $ffff,x             ; after "S0:" in dk_cmd
        sta dk_cmd+3,x
        dex
        bpl dk_snl
        rts

; SETNAM: the name (dk_cmd+3, past "S0:")
dk_setname
        lda dk_nlen             ; the name
        ldx #<dk_cmd+3
        ldy #>dk_cmd+3
        jmp K_SETNAM

; SETLFS: file 15, drive 8, secondary 15 (the command / status channel)
dk_lfs15
        lda #15
        ldx #DISK_DEV
        ldy #15
        jmp K_SETLFS

; the drive's status: its 2-digit code in disk_dos. C = 1, A = KERNAL error.
; Only once the drive answered: with no device, CHKIN's TKSA waits for the
; clock line forever.
dk_status
        lda #0
        jsr K_SETNAM
        jsr dk_lfs15
        jsr K_OPEN
        bcc +
        rts                     ; (C, A: OPEN's error)
+       ldx #15
        jsr K_CHKIN
        bcs dk_st8
        jsr K_CHRIN             ; tens (ASCII "0"-"9": the low nibble)
        and #15
        asl a                   ; * 10: * 2 + * 8
        sta dk_t
        asl a
        asl a
        adc dk_t
        sta dk_t
        jsr K_CHRIN             ; units
        and #15
        clc
        adc dk_t
        sta disk_dos
        lda #1                  ; the number after the text ("01,FILES
        sta disk_cnt            ; SCRATCHED,03,00": 3 files), for
        lda dk_wantn            ; disk_scratch only: past two commas, two
        beq dk_stx              ; digits (at most 40 bytes read)
        lda #0
        sta disk_cnt
        ldy #2
        ldx #40
-       jsr K_CHRIN
        cmp #","
        bne +
        dey
        beq ++
+       dex
        bne -
        beq dk_stx              ; (no such number: 0)
+       jsr K_CHRIN
        and #15
        asl a
        sta dk_t
        asl a
        asl a
        adc dk_t
        sta dk_t
        jsr K_CHRIN
        and #15
        clc
        adc dk_t
        sta disk_cnt
dk_stx  lda $90                 ; timeout / no device (ST bits 0, 1, 7); the
        and #$83                ; rest of the message is not read: CLOSE
        php
        jsr K_CLRCHN
        lda #15
        jsr K_CLOSE
        plp
        beq +
        lda #5
        sec
        rts
+       clc
        rts
dk_st8  pha
        lda #15
        jsr K_CLOSE
        pla
        sec
dk_st9  rts

; before the KERNAL calls: the machine saved and set up as above (A, X)
dk_enter
        sei
        ldx #2                  ; zero page $02-$ff
-       lda $00,x
        sta dk_zp-2,x
        inx
        bne -
        lda $00
        sta dk_p00
        lda $01
        sta dk_p01
        lda #$2f                ; the CPU port's directions, as at reset
        sta $00
        lda #$36                ; KERNAL, I/O (no BASIC: the program goes on
        sta $01                 ; past $a000, and the KERNAL doesn't need it)
        lda $d011
        sta dk_d011
        and #$6f                ; blank (bit 7 0: raster compare high bit)
        sta $d011
        lda $d015
        sta dk_d015
        lda #0
        sta $d015
        lda $dd00
        sta dk_dd00
        lda $dd02
        sta dk_dd02
        lda #0                  ; the KERNAL's idle serial state
        sta $90
        sta $94
        sta $a3
        sta $98
        sta $99
        sta $9d
        lda #3                  ; output: the screen
        sta $9a
        lda #$ff
        sta $91
        rts

; after them: all put back (keeps nothing; disk_bank set). Interrupts off
dk_leave
        sei
        lda $dd00
        sta disk_bank
        eor dk_dd00             ; the caller's bank bits back
        and #3
        eor $dd00
        sta $dd00
        lda dk_dd02
        sta $dd02
        ldx #2
-       lda dk_zp-2,x
        sta $00,x
        inx
        bne -
        lda dk_p00
        sta $00
        lda dk_p01
        sta $01
        lda dk_d015
        sta $d015
        lda dk_d011             ; (bit 7 as read was the raster's bit 8, not
        and #$7f                ; the caller's compare value: 0)
        sta $d011
        rts

dk_magic .byte $43, $53, 5     ; "CS", version 5
; the tweaks as made (v1/v2 files; v3: all but Bend and Vowel)
dk_twdef .byte 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 8, 0, 8, $00, 0
; v5: the limits + 1 of the first 14 (Bend, Vowel, Tone 0-16, Sidechain
; 0-8, Tune 0-16)
dk_twlim .byte 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, 17, $ff, 17 ; (twside: below)
; version 3's Bend / Vowel 0-7 (factor n/4) -> the 0-16 index of the same
; factor (seq.asm's bendf 0 1 2 3 4 5 6 7 8 10 12 14 16 20 24 28 32 /8,
; vowf ... 16 18 20 22 24 /8)
dk_v3map .byte 0, 2, 4, 6, 8, 9, 10, 11
        .include "../gen/kitv1.inc"   ; dk_kitv1: version 1's 17 sounds -> roles
dk_cmd  .byte $53, $30, $3a     ; "S0:" and the name, PETSCII (unshifted)
        .fill 16, $20
dk_nlen .byte 8
dk_catsong .byte $43, $41, $54, $53, $4f, $4e, $47      ; "CATSONG"
dk_long .byte 0                 ; the loader: a byte past 256 came
dk_full .byte 0                 ; the loader: 256 bytes are in
dk_rem  .byte 0                 ; song_unpack: the row bytes still to come

disk_err  .byte 0               ; (the outputs: see the top)
disk_st   .byte 0
disk_dos  .byte 0
disk_cnt  .byte 0               ; the drive status's first number (scratched)
dk_wantn  .byte 0               ; 1: dk_status reads that number too
disk_bank .byte 0
disk_len  .byte 0
dk_mlo  .byte 0                 ; a row's step mask
dk_mhi  .byte 0
dk_mpos .byte 0                 ; song_pack: where the row's mask goes
dk_t    .byte 0                 ; a scratch
dk_end  .byte 0                 ; the loader: bytes read (Y)
                                ; the caller's $00, $01, $d011, $d015,
                                ; $dd00, $dd02 (dk_enter / dk_leave)
dk_p00  .byte 0
dk_p01  .byte 0
dk_d011 .byte 0
dk_d015 .byte 0
dk_dd00 .byte 0
dk_dd02 .byte 0

        .weak
DISK_BUF = 0
        .endweak
        .if DISK_BUF == 0
disk_buf .fill DK_PACKMAX
dk_zp   .fill 254
        .else
disk_buf = DISK_BUF
dk_zp   = DISK_BUF + DK_PACKMAX
        .endif
dk_tmp  = dk_zp                 ; unpack scratch (dk_zp is free then):
                                ; song, then tweaks at +DK_SONGLEN
        .cerror DK_SONGLEN+DK_TWLEN > 254, "dk_tmp does not fit dk_zp"
        .cerror TWLEN != DK_TWLEN, "tweaks is not the 16 bytes disk.asm packs"
        .cerror DK_PACKMAX != 256, "the loader's limit is 256 bytes (Y wraps; a length of 0 = 256)"
        .cerror DK_MINLEN < DK_ROWS, "song_unpack: the shortest file must hold v5's tweaks"
