#-------------------------------------------------------------------------------
#Macros and defines to make life easier

.set IO_HADR,  0xFFFFC000
.set SW_LADR,  0x00008000
.set LED_LADR, 0x00004000
.set VGA_LADR, 0x00040000

.set COLOR_W,  0xF
.set COLOR_R,  0xC
.set COLOR_G,  0xA
.set COLOR_B,  0x9
.set COLOR_Y,  0xE

.set COL, 240
.set ROW, 68

#Loads the character and calls printChar (increments R16; R18 needs to be set)
.macro printCharImm char
    addi $r17, $zero, \char
    jali printChar
    addi $r16, $r16, 1
.endm

.macro friendly_print col, row, attrib_byte, str_ptr
    addi $r16, $zero, \col
    addi $r17, $zero, \row
    addi $r18, $zero, \attrib_byte
    addi $r19, $zero, \str_ptr
    jali printStr
.endm

.macro fn_enter
    addi  $sp, $sp, -8 #Allocate 1 word on the stack
    sw    $lr, ($sp) #Store the current lr on the stack
.endm

.macro fn_exit
    lw   $lr, ($sp) #Restore the original lr
    addi $sp, $sp, 8 #Free the stack space we used
    j    $lr #Return
.endm

.macro delay
    ori $r60, $zero, 0x7FFFFF
    addi $r60, $r60, -1
    beq  $r60, $zero, .+8
    beq  $zero, $zero, .-24
.endm

.macro display reg
    ori   $r4, $r1, LED_LADR  #Now load LED address into R2
    sw    \reg, ($r4)          #And store R3 into *R2
    delay
.endm
#-------------------------------------------------------------------------------
#Data segment (for the data RAM)
.data

#Stack space (grows down towards zero)
stack: .space 8*8
stack_init_head:

#String storage
hello_str: .asciz "Hello, World!"
greet_str: .asciz "Greetings from "

.align 9 #Fill 512

#-------------------------------------------------------------------------------
#Text segment (for the instruction ROM/RAM)
.text

reset:
    #Setup the stack
    addi $sp, $zero, stack_init_head

    #Load the sign-extended upper portion of the IO space in R1
    lui  $r1, IO_HADR
    ori  $r2, $zero, 0xFFFF
    ori  $r3, $r1, LED_LADR  #Now load LED address into R3
    sw   $r2, ($r3)          #And store R2 into *R3

    #Clear the display
    jali clearDisp

    #Write the plain strings
    friendly_print 115 20 0x0f hello_str
    friendly_print 110 21 0x0f greet_str

    #Write the colorful MIPS
    addi $r16, $zero, (21*COL)+125 #Row 21, Col 125
    addi $r18, $zero, COLOR_B
    printCharImm 'R'
    addi $r18, $zero, COLOR_G
    printCharImm 'a'
    addi $r18, $zero, COLOR_Y
    printCharImm 'i'
    addi $r18, $zero, COLOR_R
    printCharImm 's'
    addi $r18, $zero, COLOR_B
    printCharImm 'i'
    addi $r18, $zero, COLOR_G
    printCharImm 'n'
    addi $r18, $zero, COLOR_Y
    printCharImm '6'
    addi $r18, $zero, COLOR_R
    printCharImm '4'

    jali  reset_finloop
    addi  $r5, $zero, COL*ROW #Final character
fin_loop:
    ori   $r4, $r1, SW_LADR   #Load the switch address in R4
    lw    $r3, ($r4)          #and read into R3
    ori   $r4, $r1, LED_LADR  #Now load LED address into R4
    sw    $r3, ($r4)          #And store R3 into *R4
    jali  printChar
    addi  $r17, $r17, 1
    addi  $r18, $r18, 3
    addi  $r16, $r16, 1
    beqal $r16, $r5, reset_finloop
    ji    fin_loop             #Repeat
reset_finloop:
    addi  $r16, $zero, COL*40
    j     $lr

#Clears display
clearDisp:
    fn_enter
    addi $r16, $zero, ROW*COL
    add  $r17, $zero, $zero
    add  $r18, $zero, $zero
clearDisp_loop:
    beq  $r16, $zero, clearDisp_done
    jali printChar
    subi $r16, $r16, 1
    ji   clearDisp_loop
clearDisp_done:
    fn_exit

#Print ASCII string
# R16: Col
# R17: Row
# R18: Attribute
# R19: ASCII String (reference)
printStr:
    fn_enter
    addi $r4, $zero, COL         #R4 gets Number of Characters in Row
    mul  $r17, $zero, $r17, $r4  #R17 = NumItemsInCol*RowNum
    add  $r16, $r17, $r16        #R16 = Buffer "Character" number

printStr_nextChar:
    l8   $r17, ($r19)    #R17 = Byte in string
    beq  $r17, $zero, printStr_done #Null-Terminator
    jali printChar       #Print the character
    addi $r19, $r19, 1   #Increment pointers
    addi $r16, $r16, 1
    ji   printStr_nextChar
printStr_done:
    fn_exit

#Sends character to video display
# R16: Display Buffer Offset
# R17: ASCII Character
# R18: Packed Attribute
printChar:
    #We are a leaf function (calls no others).
    #Don't bother putting ra on the stack as we
    #won't overwrite it with function calls.
    slli $r20, $r18, 8
    or   $r20, $r20, $r17   #Prepare the packed VGA control word
    andi $r20, $r20, 0xFFFF #and mask it

    #Prepare the base VGA address in R2
    ori  $r2, $r1, VGA_LADR
    slli $r21, $r16, 3  #Shift the buffer "cell" number
    add  $r2, $r21, $r2 #Add the cell number to the address
    sw   $r20, ($r2)    #Store the result
    j    $lr

.align 11 #Fill 2K
