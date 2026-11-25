; ------------------------------------------------------------------ autoboot
; The disk's first file, "CATSYNTH64": LOAD"*",8,1 (or LOAD"CATSYNTH64",8,1)
; starts it by itself; LOAD"CATSYNTH64",8 and RUN work too. It loads
; CatBoot ("CATBOOT", catboot.asm, at $c000) and starts it.
;
; Loaded where it says ($02a7, ",1"), the file runs over $0300-$0303:
; BASIC's error vector (put back as the ROM has it) and its main loop's,
; which BASIC calls once the LOAD is done: here, the code below. Loaded at
; $0801 instead (no ",1"), its first 12 bytes are the BASIC line
; 2026 SYS2061 and the code comes at 2061. So the code may only use
; branches, fixed addresses and the ROM: it runs at $02b3 or at $080d.
;
;   64tass -C -a src/autoboot.asm -o build/autoboot.prg

SETLFS  = $ffba
SETNAM  = $ffbd
LOAD    = $ffd5
NAME    = $0200                 ; (BASIC's input buffer: the name is built
                                ; there, the code's own address unknown)
CB      = $c000                 ; CatBoot's start (and load address)
ABNAME  = "catboot"             ; (-a: lower case = PETSCII capitals)

        * = $02a7
        .byte $0b, $08          ; at $0801: the line's link ($080b),
        .word 2026              ; its number,
        .text $9e, "2061", 0    ; SYS2061 (2061 = $080d: the code there)
        .word 0                 ; the end of the program
start   lda #$83                ; BASIC's main loop back ($a483): nothing
        sta $0302               ; starts this again
        lda #$a4
        sta $0303
        .for i = 0, i < len(ABNAME), i += 1
        lda #ABNAME[i]
        sta NAME + i
        .next
        lda #len(ABNAME)
        ldx #<NAME
        ldy #>NAME
        jsr SETNAM
        ldx $ba                 ; the drive this came from
        ldy #1                  ; (,1: to $c000)
        jsr SETLFS
        lda #0
        jsr LOAD
        bcs +
        jmp CB
+       tax                     ; the KERNAL's error = BASIC's ("FILE NOT
        jmp ($0300)             ; FOUND"...)

        .cerror start != $02b3, "the code must start at $02b3 ($080d at $0801)"
        .cerror * > $0300, "the code must end by $02ff"
        .fill $0300 - *, 0
        .word $e38b             ; $0300: BASIC's error vector, as at reset
        .word start             ; $0302: BASIC's main loop: the code above
