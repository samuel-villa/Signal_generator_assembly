;----------------------------------------------------------------------------
;   --- Dossier SLP ---						Samuel CIULLA
;   
;   Proteus Project => 16F917_generator.pdsprj   
;
;   Application  : générateur de signaux
;   PIC		 : 16F917
;   Bus		 : SPI
;   Sortie signal: DAC 0808 connection directe au PIC
;   Entrée signal: clavier numérique 16 touches    
;   Paramètres	 : fréquence, type et rapport cyclique du signal
;   LCD (4x20)	 : connection au bus SPI via IO expander 16 bits
;
;   Buttons:
;   RUN/CONGIF: enable/disable configuration mode
;   '0-9'     : NOT USED
;   ON/C      : Reset button, set middle range frequency and duty cycle at 50%
;   '='	      : switch waveform type
;   '÷'	      : decrease frequency
;   'x'	      : increase frequency
;   '-'	      : decrease duty cycle (square and triangle waveform)
;   '+'	      : increase duty cycle (square and triangle waveform)
;
;----------------------------------------------------------------------------
; PIC configuration
;----------------------------------------------------------------------------
PROCESSOR 16F917
#include <xc.inc>

;configuration words
CONFIG FOSC=HS 			// HS Oscillator
CONFIG WDTE=OFF			// WDT disabled
CONFIG PWRTE=OFF		// PWRT disabled
CONFIG CP=OFF			// Program memory unprotected

    
;----------------------------------------------------------------------------
; definitions
;----------------------------------------------------------------------------
; MCP23S17 Expander		// WARNING: if IOCON.BANK=1 registers must be changed
#define	MCP_ADR	    0x40	// I/O Expander address (bit0=0=write)
#define	MCP_IOCON   0x0A	// IOCON register
#define	MCP_IODIRA  0x00	// IODIRA register
#define	MCP_IODIRB  0x01	// IODIRB register
#define	MCP_GPIOA   0x12	// GPIOA register
#define	MCP_GPIOB   0x13	// GPIOB register
#define	MCP_OLATA   0x14	// OLATA register
#define	MCP_OLATB   0x15	// OLATB register
#define CARRY	    STATUS,0	// carry bit
    
; PIC16F917
#define LED1	    PORTA,0	// ON when in config mode
#define RUN_CONF    PORTA,1	// switch between run and config mode
#define BUT_SWITCH  PORTB,2	// switch waveform type
#define INT_TICK    PORTC,0	// tick signal
#define SPI_CS	    PORTC,3	// chip select bit (for MCP23S17)
    
; WAVEFORMS
#define SIGSQR	    0x01	// square
#define SIGRMP	    0x02	// ramp
#define SIGSAW	    0x04	// saw tooth
#define SIGTRI	    0x08	// triangle
    
; LCD lines
#define	LINE1	    0x80	// position the cursor to beg of line 1
#define	LINE2	    0xC0	// position the cursor to beg of line 2
#define	LINE3	    0x94	// position the cursor to beg of line 3
#define	LINE4	    0xD4	// position the cursor to beg of line 4
    
; Duty Cycle (period = 0xFF)
#define	TEN_PC	    0x19	// 10% of 0xFF
#define	TWENTY_PC   0x33	// 20% of 0xFF
#define	THIRTY_PC   0x4C	// 30% of 0xFF
#define	FORTY_PC    0x66	// 40% of 0xFF
#define	FIFTY_PC    0x7F	// 50% of 0xFF
#define	SIXTY_PC    0x99	// 60% of 0xFF
#define	SEVENTY_PC  0xB3	// 70% of 0xFF
#define	EIGHTY_PC   0xCC	// 80% of 0xFF
#define	NINETY_PC   0xE6	// 90% of 0xFF


;----------------------------------------------------------------------------
; variable zone declaration
;----------------------------------------------------------------------------
PSECT udata_bank0
t_base:	DS 1	; tempo time base
max:	DS 1	; 0xFF
tri_cpt:DS 1	; counter for triangle signal
cpt:	DS 1	; counter variable
sig_typ:DS 1	; signal type
kb_var:	DS 1	; pressed button data
duty_cy:DS 1	; duty cycle
dcy_ind:DS 1	; duty cycle indicator
c1:     DS 1	; tempo1
c2:	DS 1	; tempo2
c3:	DS 1	; tempo3
c4:	DS 1	; tempo4
t_hi:	DS 1	; tempo HIGH
t_lo:	DS 1	; tempo LOW
sig:	DS 1	; signal
lp_down:DS 1	; loop counter
lp_up:	DS 1	; loop counter
w_tmp:	DS 1	; w buffer
s_tmp:	DS 1	; buffer
mcp_val:DS 1	; MCP23S17 value
lcdcmd: DS 1	; LCD command
lcddat: DS 1	; LCD data
char:	DS 1	; char to be sent to LCD
cmd:	DS 1	; LCD command
MSD:	DS 1	; Digit de conversion BCD
MsD:	DS 1	; Digit de conversion BCD
LSD:	DS 1	; Digit de conversion BCD
    
    
;----------------------------------------------------------------------------
; reset
;----------------------------------------------------------------------------
PSECT resetVec,class=CODE,delta=2
resetVec:
    goto init
    
    
;----------------------------------------------------------------------------
; interruption
;----------------------------------------------------------------------------
PSECT interVec,class=CODE,delta=2
interVec:
    movwf   w_tmp	; sauver registre W
    swapf   STATUS,w	; swap status avec résultat dans w
    movwf   s_tmp	; sauver status swapp
    
    bsf	    INT_TICK	; generate tick
    bcf	    INT_TICK
    call    signal
    
end_inter:
    bcf	    CCP1IF
    bcf	    STATUS,0
    
restorereg:
    swapf   s_tmp,w	; swap ancien status, résultat dans w
    movwf   STATUS	; restaurer status
    swapf   w_tmp,f	; Inversion L et H de l'ancien W
    swapf   w_tmp,w  	; Réinversion de L et H dans W
    retfie  		; return from interrupt
     

;----------------------------------------------------------------------------
; initialization
;----------------------------------------------------------------------------
PSECT code
init:
    banksel PORTA
    clrf    PORTA	; clear PORTA
    clrf    PORTB	; clear PORTB
    clrf    PORTC	; clear PORTC
    clrf    PORTD	; clear PORTD
    clrf    PORTE	; clear PORTE
    clrf    ADCON0	; AD converter not needed
    clrf    CCP2CON	; clear CCP2 (PORTD multiplexed output)
    
    banksel TRISA
    movlw   0x02	; run/config button INPUT
    movwf   TRISA	; TRISA OUTPUT (except pin1)
    movlw   0xF0	; only 4 outputs needed
    movwf   TRISB	; half OUTPUT half INPUT
    clrf    TRISC	; OUTPUT
    clrf    TRISD	; OUTPUT
    clrf    TRISE	; OUTPUT
    clrf    ANSEL	; all pins as digital I/O
    movlw   0x07	; comp off and pins as digital I/O
    movwf   CMCON0	; comparator not needed
    
    banksel LCDCON
    clrf    LCDCON	; not needed
    clrf    LVDCON	; not needed
    
    banksel IOCB
    movlw   0x00
    movwf   IOCB	; disable RB4-7 for interrupt
    
    banksel TRISC
    bcf	    TRISC0	; Interrupt tick
    bsf	    TRISC1	; Config CCP1
    bsf	    TRISC2	; Config CCP1
    bsf	    TRISC5	; Config CCP1
    
    banksel OPTION_REG
    bcf	    T0CS
    bcf	    PSA		; TMR0 prescaler
    bsf	    PS0
    bsf	    PS1
    bsf	    PS2
    
    banksel PIE1
    bsf	    CCP1IE	; CCP interrupt enabled

    banksel PORTD
    movlw   0x0B	; Compare with interrupt and special trigger
    movwf   CCP1CON
        
    movlw   0x01	; enable timer 1
    movwf   T1CON
    bsf	    T1CKPS0	; prescaler t1
    bsf	    T1CKPS1	
    movlw   0x00	; prescaler CCP special trigger
    movwf   CCPR1H
    movlw   0x20
    movwf   CCPR1L
    
    call    SPI_init
    call    MCP_init
    call    LCD_start
    call    init_var
    
    movlw   SIGSQR	; init waveform
    movwf   sig_typ,f
    
restart:
    bcf	    PORTA,0	; LED OFF
    call    LCD_display	; must be BEFORE interrupts enabling
    
    bcf	    CCP1IF	; clear ccp interrupt flag
    bsf	    PEIE	; enable peripheral interrupts
    bsf	    GIE		; enable global interrupts
    
    
    
;----------------------------------------------------------------------------
; main program
;----------------------------------------------------------------------------
main:
    btfsc   RUN_CONF	; is RUN/CONFIG button on ?
    goto    run_config	; yes, go to CONFIG mode
    goto    main
    
    
    
;----------------------------------------------------------------------------
; run/config button. 0 = RUN; 1 = CONFIG    
;----------------------------------------------------------------------------
run_config:
    btfss   RUN_CONF	; is RUN/CONFIG button on ?
    goto    restart	; no, go to RUN mode
    bcf	    GIE		; disable all interrupts
    bsf	    PORTA,0	; LED ON
    
    call    scan_keypad
    movwf   kb_var,f
    btfsc   kb_var,6	; 'ON/C' pushed ?
    call    reset_g
    btfsc   kb_var,4	; bit 4 change ?
    call    store
    
    goto    run_config
    
    

;----------------------------------------------------------------------------
; initialize all variables
;----------------------------------------------------------------------------
init_var:
    movlw   0x00
    movwf   sig,f
    movwf   kb_var,f
    movlw   0x01
    movwf   cpt,f
    movlw   0xFF
    movwf   max,f
    movlw   FIFTY_PC	; init signal duty cycle timing at 50%
    movwf   t_lo,f	; 0x7F	(50%)
    movwf   t_hi,f	; 0x7F	(50%)
    movlw   0x32
    movwf   duty_cy,f	; init duty cycle display at 50%
    movlw   0x0F
    movwf   dcy_ind,f	; init duty cycle indicator
    movlw   0x04
    movwf   t_base,f	; init time base (go from 0x01 to 0x0F)
    movlw   0x01
    movwf   tri_cpt,f
    clrf    PORTB
    return
    
    
    
;----------------------------------------------------------------------------
; reset variables at a standard value
;----------------------------------------------------------------------------
reset_g:
    btfsc   kb_var,5	; bit 5 change ?
    return		; yes, it's not ON/C button (it's a number)
    call    init_var	; no, it's ON/C button, reset
    call    LCD_display
    return
    
    
;----------------------------------------------------------------------------
; store value in result
;----------------------------------------------------------------------------
store:
    btfss   kb_var,5	; is it a number ?
    goto    operation	; no, it's an operation, no storing
    return
    
    
;----------------------------------------------------------------------------
; operation test
;----------------------------------------------------------------------------
operation:
    btfss   kb_var,3	; is it '=' ?
    goto    switch_wf	; switch waveform type
    btfsc   kb_var,7
    goto    set_frq	; frequency settings
    goto    dc_sett	; duty cycle settings
    return
    
    
;----------------------------------------------------------------------------
; Set Duty Cycle (only available for square and triangle signals)
;----------------------------------------------------------------------------
dc_sett:
    btfsc   sig_typ,0
    goto    st_dc_set
    btfsc   sig_typ,1
    goto    run_config
    btfsc   sig_typ,2
    goto    run_config
    btfsc   sig_typ,3
    goto    st_dc_set

st_dc_set:   
    btfss   kb_var,0	; test if + or -
    goto    minus	; -
    goto    plus	; +
minus:
    btfsc   PORTB,6
    goto    $-1
    btfss   dcy_ind,0	; if 10% can't get lower
    goto    run_config
    bcf	    CARRY
    rrf	    dcy_ind
    movlw   0x0A	; sub 10
    subwf   duty_cy,f	;
    call    LCD_display
    call    dc_check
    goto    run_config	; go back
plus:
    btfsc   PORTB,7
    goto    $-1
    btfsc   dcy_ind,7	; if 90% can't get higher
    goto    run_config
    bsf	    CARRY
    rlf	    dcy_ind
    movlw   0x0A	; add 10
    addwf   duty_cy,f	;
    call    LCD_display
    call    dc_check
    goto    run_config	; go back
    
    
;----------------------------------------------------------------------------
; check Duty Cycle
;----------------------------------------------------------------------------
dc_check:
    btfsc   dcy_ind,7
    call    dc_90
    btfsc   dcy_ind,6
    call    dc_80
    btfsc   dcy_ind,5
    call    dc_70
    btfsc   dcy_ind,4
    call    dc_60
    btfsc   dcy_ind,3
    call    dc_50
    btfsc   dcy_ind,2
    call    dc_40
    btfsc   dcy_ind,1
    call    dc_30
    btfsc   dcy_ind,0
    call    dc_20
    call    dc_10
    
    
;----------------------------------------------------------------------------
; Set frequency - common to all signal types
;----------------------------------------------------------------------------
set_frq:
    btfss   kb_var,0	; test if / or *
    goto    inc_tb	; /
    goto    dec_tb	; *
dec_tb:
    btfsc   PORTB,5
    goto    $-1
    btfsc   t_base,0	; can't get lower
    goto    run_config
    bcf	    CARRY
    rrf	    t_base
    goto    end_check
inc_tb:
    btfsc   PORTB,4
    goto    $-1
    btfsc   t_base,4	; can't get higher
    goto    run_config
    bcf	    CARRY
    rlf	    t_base
    goto    end_check
end_check:
    call    LCD_display
    goto    run_config	; go back

    
;----------------------------------------------------------------------------
; switch waveform type
;----------------------------------------------------------------------------
switch_wf:
    btfsc   PORTB,7
    goto    $-1
    btfsc   sig_typ,3
    goto    set_sqr
    bcf	    CARRY	; clear carry bit
    rlf	    sig_typ,f	; yes, rotate left
    call    LCD_display
    goto    run_config
    
set_sqr:
    movlw   SIGSQR
    movwf   sig_typ,f
    call    LCD_display
    goto    run_config
    
    
;----------------------------------------------------------------------------
; signal generation
;----------------------------------------------------------------------------
signal:
    btfsc   RUN_CONF
    goto    run_config
    btfsc   sig_typ,0
    goto    square
    btfsc   sig_typ,1
    goto    ramp
    btfsc   sig_typ,2
    goto    saw_tooth
    btfsc   sig_typ,3
    goto    tri
    goto    signal
    
    
;----------------------------------------------------------------------------
; square signal construction
;----------------------------------------------------------------------------
square:
    movf    sig,w
    movwf   PORTD,f
    btfsc   sig,0
    call    tempo_sq_H
    btfss   sig,0
    call    tempo_sq_L
    comf    sig
    return
    

;----------------------------------------------------------------------------
; set Duty Cycle at 10/90
;----------------------------------------------------------------------------
dc_10:
    movlw   TEN_PC
    movwf   t_hi,f
    movlw   NINETY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 20/80
;----------------------------------------------------------------------------
dc_20:
    movlw   TWENTY_PC
    movwf   t_hi,f
    movlw   EIGHTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 30/70
;----------------------------------------------------------------------------
dc_30:
    movlw   THIRTY_PC
    movwf   t_hi,f
    movlw   SEVENTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 40/60
;----------------------------------------------------------------------------
dc_40:
    movlw   FORTY_PC
    movwf   t_hi,f
    movlw   SIXTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 50/50
;----------------------------------------------------------------------------
dc_50:
    movlw   FIFTY_PC
    movwf   t_hi,f
    movlw   FIFTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 60/40
;----------------------------------------------------------------------------
dc_60:
    movlw   SIXTY_PC
    movwf   t_hi,f
    movlw   FORTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 70/30
;----------------------------------------------------------------------------
dc_70:
    movlw   SEVENTY_PC
    movwf   t_hi,f
    movlw   THIRTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 80/20
;----------------------------------------------------------------------------
dc_80:
    movlw   EIGHTY_PC
    movwf   t_hi,f
    movlw   TWENTY_PC
    movwf   t_lo,f
    goto    run_config
    
;----------------------------------------------------------------------------
; set Duty Cycle at 90/10
;----------------------------------------------------------------------------
dc_90:
    movlw   NINETY_PC
    movwf   t_hi,f
    movlw   TEN_PC
    movwf   t_lo,f
    goto    run_config
    
    
    
    
;----------------------------------------------------------------------------
; ramp (going UP) signal construction
;----------------------------------------------------------------------------
ramp:
    movf    cpt,w	
    addwf   PORTD,f	; generate waveform
    call    tempo_rst
    return
    
;----------------------------------------------------------------------------
; sawtooth (going DOWN) signal construction
;----------------------------------------------------------------------------
saw_tooth:
    movf    cpt,w
    subwf   PORTD,f	; generate waveform
    call    tempo_rst
    return
    

;----------------------------------------------------------------------------
; triangle signal construction
;----------------------------------------------------------------------------
tri:
    movlw   0x00
    movwf   lp_down,f
    movwf   lp_up,f
    clrf    PORTD
go_up:
    btfsc   RUN_CONF
    goto    run_config
    bcf	    STATUS,2	; reset 0 bit
    movlw   0x00
    movwf   lp_down,f	; reset "go_down" loop counter
    movf    tri_cpt,w
    addwf   PORTD,f	
    call    tempo_sq_H
    incf    lp_up,f	; counter++
    movf    lp_up,w
    subwf   max,w	; is counter = 255 ?
    btfsc   STATUS,2	; is zero bit = 1 ?
    goto    go_down	; yes, go down
    goto    go_up	; no, loop
go_down:
    btfsc   RUN_CONF	; condition to exit the loop
    goto    run_config
    bcf	    STATUS,2	; reset 0 bit
    movlw   0x00
    movwf   lp_up,f	; reset "go_up" loop counter
    movf    tri_cpt,w
    subwf   PORTD,f
    call    tempo_sq_L
    incf    lp_down,f	; counter++
    movf    lp_down,w
    subwf   max,w	; is counter = 255 ?
    btfsc   STATUS,2	; is zero bit = 1 ?
    goto    go_up	; yes, go up
    goto    go_down	; no, loop

    
    
    
    
;----------------------------------------------------------------------------
; scan keypad
;----------------------------------------------------------------------------
scan_keypad:
    banksel PORTB
    
    movlw   0x01	; 00000001
    movwf   PORTB	; scan col 1
    btfsc   PORTB,4	; push 7 ?
    retlw   0xF7
    btfsc   PORTB,5	; push nb 4 ?
    retlw   0xF4
    btfsc   PORTB,6	; push nb 1 ?
    retlw   0xF1
    btfsc   PORTB,7	; push ON/C ?
    retlw   0x5B	; 01011011
    
    movlw   0x02	; 00000010
    movwf   PORTB	; scan col 2
    btfsc   PORTB,4	; push nb 8 ?
    retlw   0xF8
    btfsc   PORTB,5	; push nb 5 ?
    retlw   0xF5
    btfsc   PORTB,6	; push nb 2 ?
    retlw   0xF2
    btfsc   PORTB,7	; push 0 ?
    retlw   0xF0
    
    movlw   0x04	; 00000100
    movwf   PORTB	; scan col 3
    btfsc   PORTB,4	; push nb 9 ?
    retlw   0xF9
    btfsc   PORTB,5	; push nb 6 ?
    retlw   0xF6
    btfsc   PORTB,6	; push nb 3 ?
    retlw   0xF3
    btfsc   PORTB,7	; push = ?
    retlw   0x12	; 00010010
    
    movlw   0x08	; 00001000
    movwf   PORTB	; scan col 4
    btfsc   PORTB,4	; push / ?
    retlw   0x9C	; 10011100
    btfsc   PORTB,5	; push * ?
    retlw   0x9D	; 10011101
    btfsc   PORTB,6	; push - ?
    retlw   0x1E	; 00011110
    btfsc   PORTB,7	; push + ?
    retlw   0x1F	; 00011111
    
    movlw   0x00	; 00000000
    movwf   PORTB	; no scan
    
    retlw   0x00	; return 0
    
    
    
;----------------------------------------------------------------------------
; Initialization of the MCP23S17
;----------------------------------------------------------------------------
MCP_init:
			; IOCON register configuration
    bcf	    SPI_CS
    movlw   MCP_ADR
    call    MCP_send
    movlw   MCP_IOCON
    call    MCP_send
    ;movlw   0xA0	; BANK = 1 | SEQOP = 1 => PROTEUS PROBLEM !
    movlw   0x20	; BANK = 0 | SEQOP = 1
    call    MCP_send
    bsf	    SPI_CS
			; IODIRA register configuration
    bcf	    SPI_CS
    movlw   MCP_ADR
    call    MCP_send
    movlw   MCP_IODIRA
    call    MCP_send
    movlw   0x3F	; only use PORTA pins 6 and 7
    call    MCP_send
    bsf	    SPI_CS
			; IODIRB register configuration
    bcf	    SPI_CS
    movlw   MCP_ADR
    call    MCP_send
    ;movlw   0x10	; register IODIRB (IOCON.BANK=1) => PROTEUS PROBLEM !
    movlw   MCP_IODIRB
    call    MCP_send
    movlw   0x00	; PORTB as OUTPUT
    call    MCP_send
    bsf	    SPI_CS
    return
    


;----------------------------------------------------------------------------
; transmit data to the MCP23S17 PORTA
;----------------------------------------------------------------------------
MCP_to_A:
    movwf   lcdcmd,f	; load parameter (w) into variable
    bcf	    SPI_CS	; Select chip lowered
    movlw   MCP_ADR
    call    MCP_send
    movlw   MCP_GPIOA
    call    MCP_send
    movf    lcdcmd,w
    call    MCP_send
    bsf	    SPI_CS	; De-select chip
    return
    
;----------------------------------------------------------------------------
; transmit data to the MCP23S17 PORTB
; value is stored in w before calling this instruction
;----------------------------------------------------------------------------
MCP_to_B:
    movwf   lcddat,f	; load parameter (w) into variable
    bcf	    SPI_CS	; Select chip lowered
    movlw   MCP_ADR
    call    MCP_send
    movlw   MCP_GPIOB
    call    MCP_send
    movf    lcddat,w
    call    MCP_send
    bsf	    SPI_CS	; De-select chip
    return
    
    
;----------------------------------------------------------------------------
; send 1 byte to the MCP23S17 through SPI
; value is stored in w before calling this instruction
;----------------------------------------------------------------------------
MCP_send:
    bcf	    SSPIF
    movwf   SSPBUF
    btfss   SSPIF
    goto    $-1
    return
    
    
;----------------------------------------------------------------------------
; LCD : Send init sequence
;----------------------------------------------------------------------------
LCD_start:
    movlw   0x33
    call    LCD_cmd
    call    tempo_l
    movlw   0x33
    call    LCD_cmd
    call    tempo_l
    movlw   0x38
    call    LCD_cmd
    call    tempo_l
    movlw   0x0C	; cursor off
    call    LCD_cmd
    call    tempo_l
    movlw   0x06
    call    LCD_cmd
    call    tempo_l
    return
    

    
    
;----------------------------------------------------------------------------
; update LCD
;----------------------------------------------------------------------------
LCD_display:
    movlw   0x01	; clear
    call    LCD_cmd
    call    tempo_l
    
    movlw   LINE1
    call    LCD_cmd
    call    tempo_l
    call    LCD_title
    
    movlw   LINE2
    call    LCD_cmd
    call    tempo_l
    call    LCD_freq
    
    movlw   LINE3
    call    LCD_cmd
    call    tempo_l
    call    LCD_wf
    
    movlw   LINE4
    call    LCD_cmd
    call    tempo_l
    call    LCD_dc
    
    return
    
    
;----------------------------------------------------------------------------
; LCD display frequencies based on 't_base' variable
; For data displayed to be correct Microprocessor MUST RUN at 20 MHz
;----------------------------------------------------------------------------
LCD_freq:
    movlw   'F'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    movlw   'Q'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    movlw   ':'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    
    btfsc   sig_typ,0
    goto    disp_sq_fq
    btfsc   sig_typ,1
    goto    disp_rs_fq
    btfsc   sig_typ,2
    goto    disp_rs_fq
    btfsc   sig_typ,3
    goto    disp_tr_fq
       
// list of frequencies hard coded for triangle signal
disp_tr_fq:
    btfsc   t_base,4
    call    LCD_frq1_tr
    btfsc   t_base,3
    call    LCD_frq2_tr
    btfsc   t_base,2
    call    LCD_frq3_tr
    btfsc   t_base,1
    call    LCD_frq4_tr
    btfsc   t_base,0
    call    LCD_frq5_tr
    goto    disp_hz
    
// list of frequencies hard coded for ramp and saw tooth signals
disp_rs_fq:
    btfsc   t_base,4
    call    LCD_frq1_rs
    btfsc   t_base,3
    call    LCD_frq2_rs
    btfsc   t_base,2
    call    LCD_frq3_rs
    btfsc   t_base,1
    call    LCD_frq4_rs
    btfsc   t_base,0
    call    LCD_frq5_rs
    goto    disp_hz
    
// list of frequencies hard coded for square signal
disp_sq_fq:
    btfsc   t_base,4
    call    LCD_frq1_sq
    btfsc   t_base,3
    call    LCD_frq2_sq
    btfsc   t_base,2
    call    LCD_frq3_sq
    btfsc   t_base,1
    call    LCD_frq4_sq
    btfsc   t_base,0
    call    LCD_frq5_sq
    goto    disp_hz
    
disp_hz:
    movlw   ' '
    call    LCD_char
    movlw   'H'
    call    LCD_char
    movlw   'z'
    call    LCD_char
    
    return
    
    
;----------------------------------------------------------------------------
; LCD display frequency 390 Hz (t_base = 0x10, µP at 20 MHz)
;----------------------------------------------------------------------------
LCD_frq1_sq:
    movlw   '3'
    call    LCD_char
    movlw   '7'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 649 Hz (t_base = 0x08, µP at 20 MHz)
;----------------------------------------------------------------------------
LCD_frq2_sq:
    movlw   '6'
    call    LCD_char
    movlw   '4'
    call    LCD_char
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 1087 Hz (t_base = 0x04, µP at 20 MHz)
;----------------------------------------------------------------------------
LCD_frq3_sq:
    movlw   '1'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    movlw   '8'
    call    LCD_char
    movlw   '7'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 1600 Hz (t_base = 0x02, µP at 20 MHz)
;----------------------------------------------------------------------------
LCD_frq4_sq:
    movlw   '1'
    call    LCD_char
    movlw   '6'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 2410 Hz (t_base = 0x01, µP at 20 MHz)
;----------------------------------------------------------------------------
LCD_frq5_sq:
    movlw   '2'
    call    LCD_char
    movlw   '4'
    call    LCD_char
    movlw   '1'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD display frequency 5 Hz (t_base = 0x10, µP at 20 MHz) ramp and saw signals
;----------------------------------------------------------------------------
LCD_frq1_rs:
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 10 Hz (t_base = 0x08, µP at 20 MHz) ramp and saw signals
;----------------------------------------------------------------------------
LCD_frq2_rs:
    movlw   '1'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 15 Hz (t_base = 0x04, µP at 20 MHz) ramp and saw signals
;----------------------------------------------------------------------------
LCD_frq3_rs:
    movlw   '1'
    call    LCD_char
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 25 Hz (t_base = 0x02, µP at 20 MHz) ramp and saw signals
;----------------------------------------------------------------------------
LCD_frq4_rs:
    movlw   '2'
    call    LCD_char
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 38 Hz (t_base = 0x01, µP at 20 MHz) ramp and saw signals
;----------------------------------------------------------------------------
LCD_frq5_rs:
    movlw   '3'
    call    LCD_char
    movlw   '8'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 1,5 Hz (t_base = 0x10, µP at 20 MHz) triangle signal
;----------------------------------------------------------------------------
LCD_frq1_tr:
    movlw   '1'
    call    LCD_char
    movlw   '.'
    call    LCD_char
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 2,7 Hz (t_base = 0x08, µP at 20 MHz) triangle signal
;----------------------------------------------------------------------------
LCD_frq2_tr:
    movlw   '2'
    call    LCD_char
    movlw   '.'
    call    LCD_char
    movlw   '7'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 4,7 Hz (t_base = 0x04, µP at 20 MHz) triangle signal
;----------------------------------------------------------------------------
LCD_frq3_tr:
    movlw   '4'
    call    LCD_char
    movlw   '.'
    call    LCD_char
    movlw   '7'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 7,5 Hz (t_base = 0x02, µP at 20 MHz) triangle signal
;----------------------------------------------------------------------------
LCD_frq4_tr:
    movlw   '7'
    call    LCD_char
    movlw   '.'
    call    LCD_char
    movlw   '5'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display frequency 10,7 Hz (t_base = 0x01, µP at 20 MHz) triangle signal
;----------------------------------------------------------------------------
LCD_frq5_tr:
    movlw   '1'
    call    LCD_char
    movlw   '0'
    call    LCD_char
    movlw   '.'
    call    LCD_char
    movlw   '7'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD display 'Duty Cycle'
;----------------------------------------------------------------------------
LCD_dc:
    movlw   'D'
    call    LCD_char
    movlw   'C'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    movlw   ' '
    call    LCD_char
    movlw   ':'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    movf    duty_cy,w	    ; display dc in %
    call    bin_bcd
    movf    MSD,W
    ;call    LCD_char	    ; MSD OFF, not needed cause we get max 90%
    movf    MsD,W
    call    LCD_char
    movf    LSD,W
    call    LCD_char
    movlw   '%'
    call    LCD_char
    
    return
    
;----------------------------------------------------------------------------
; LCD display 'waveform' and waveform type depending on selection
;----------------------------------------------------------------------------
LCD_wf:
    movlw   'W'
    call    LCD_char
    movlw   'A'
    call    LCD_char
    movlw   'V'
    call    LCD_char
    movlw   'E'
    call    LCD_char
    movlw   ':'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    
    btfsc   sig_typ,0
    call    LCD_wf_sqr
    btfsc   sig_typ,1
    call    LCD_wf_rmp
    btfsc   sig_typ,2
    call    LCD_wf_saw
    btfsc   sig_typ,3
    call    LCD_wf_tri
    
    return
    
;----------------------------------------------------------------------------
; LCD display Triangle waveform
;----------------------------------------------------------------------------
LCD_wf_tri:
    movlw   'T'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    movlw   'I'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD display Square waveform
;----------------------------------------------------------------------------
LCD_wf_sqr:
    movlw   'S'
    call    LCD_char
    movlw   'Q'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD display Ramp waveform
;----------------------------------------------------------------------------
LCD_wf_rmp:
    movlw   'R'
    call    LCD_char
    movlw   'M'
    call    LCD_char
    movlw   'P'
    call    LCD_char
    return
    
;----------------------------------------------------------------------------
; LCD display Saw Tooth waveform
;----------------------------------------------------------------------------
LCD_wf_saw:
    movlw   'S'
    call    LCD_char
    movlw   'A'
    call    LCD_char
    movlw   'W'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD display TITLE 'Waveform Generator'
;----------------------------------------------------------------------------
LCD_title:
    movlw   ' '
    call    LCD_char
    movlw   'W'
    call    LCD_char
    movlw   'A'
    call    LCD_char
    movlw   'V'
    call    LCD_char
    movlw   'E'
    call    LCD_char
    movlw   'F'
    call    LCD_char
    movlw   'O'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    movlw   'M'
    call    LCD_char
    movlw   ' '
    call    LCD_char
    movlw   'G'
    call    LCD_char
    movlw   'E'
    call    LCD_char
    movlw   'N'
    call    LCD_char
    movlw   'E'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    movlw   'A'
    call    LCD_char
    movlw   'T'
    call    LCD_char
    movlw   'O'
    call    LCD_char
    movlw   'R'
    call    LCD_char
    return
    
    
;----------------------------------------------------------------------------
; LCD send command
;----------------------------------------------------------------------------
LCD_cmd:
    movwf   cmd		; Command to be sent must be in W
    movlw   0x00
    call    MCP_to_A	; RS = 0
    movf    cmd,w
    call    MCP_to_B	; send command to LCD
    movlw   0x80
    call    MCP_to_A	; EN = 1
    call    tempo
    movlw   0x00	; EN = 0
    call    MCP_to_A
    return
    
    
;----------------------------------------------------------------------------
; send character to LCD
;----------------------------------------------------------------------------
LCD_char:
    movwf   char	; Character to be sent must be in W
    movlw   0x40
    call    MCP_to_A	; RS = 1
    movf    char,w
    call    MCP_to_B	; send char to LCD
    movlw   0xC0
    call    MCP_to_A	; EN = 1    (RS = 1)
    call    tempo
    movlw   0x40	; EN = 0    (RS = 1)
    call    MCP_to_A
    return
    
    
    
;----------------------------------------------------------------------------
; PIC16F917 SPI protocol initialization
;----------------------------------------------------------------------------
SPI_init:
    banksel TRISC
    bcf	    TRISC,0	; 
    bcf	    TRISC,3	; Config SPI CS
    bcf	    TRISC,4	; Config SPI SD0
    bcf	    TRISC,5	; interrupt tick
    bcf	    TRISC,6	; Config SPI SCK
    bsf	    TRISC,7	; Config SPI SDI
    banksel PORTC	; CS inverted
    bsf	    SPI_CS
    bcf	    PORTC,5
    banksel SSPSTAT
    movlw   0x00
    movwf   SSPSTAT
    bcf	    CKE		; Rising edge
    banksel SSPCON
    movlw   0x00	; SPI master F/4
    movwf   SSPCON
    bsf	    SSPEN
    return
    
    
    
;----------------------------------------------------------------------------
; Binary (8-bit) to BCD : 255 = highest possible result, value in w
;----------------------------------------------------------------------------
bin_bcd:
    clrf    MSD
    clrf    MsD
    movwf   LSD			;move value to LSD
ghundreth:	
    movlw   100			;subtract 100 from LSD
    subwf   LSD,W
    btfss   CARRY		;is value greater then 100
    goto    gtenth		;NO goto tenths
    movwf   LSD			;YES, move subtraction result into LSD
    incf    MSD,F		;increment hundreths
    goto    ghundreth
gtenth:
    movlw   10			;take care of tenths
    subwf   LSD,W
    btfss   CARRY
    goto    over		;finished conversion
    movwf   LSD
    incf    MsD,F		;increment tenths position
    goto    gtenth
over:				;0 - 9, high nibble = 3 for LCD
    movf    MSD,W		;get BCD values ready for LCD display
    xorlw   0x30		;convert to LCD digit
    movwf   MSD
    movf    MsD,W
    xorlw   0x30		;convert to LCD digit
    movwf   MsD
    movf    LSD,W
    xorlw   0x30		;convert to LCD digit
    movwf   LSD
    return

    
    
;----------------------------------------------------------------------------
; Tempo for square signal HIGH
;----------------------------------------------------------------------------
tempo_sq_H:
    movf    t_hi,w
    goto    tempo_sig
    
;----------------------------------------------------------------------------
; Tempo for square signal LOW
;----------------------------------------------------------------------------
tempo_sq_L:
    movf    t_lo,w
    goto    tempo_sig
    
;----------------------------------------------------------------------------
; Tempo for ramp and saw tooth signal
;----------------------------------------------------------------------------
tempo_rst:
    movlw   0x40
    goto    tempo_sig
    
;----------------------------------------------------------------------------
; Tempo used for signal generation (all signals)
;----------------------------------------------------------------------------
tempo_sig:
    movwf   c3
tempo_sig1:
    movf    t_base,w		; general time base
    movwf   c4
tempo_sig2:
    decfsz  c4,f
    goto    tempo_sig2
    decfsz  c3,f
    goto    tempo_sig1
    return
    
    
    
;----------------------------------------------------------------------------
; Tempo short, no parameter (creates parameter for 'tempo')
;----------------------------------------------------------------------------
tempo_s:
    movlw   0x40
    goto    tempo
    
;----------------------------------------------------------------------------
; Tempo long, no parameter (creates parameter for 'tempo')
;----------------------------------------------------------------------------
tempo_l:
    movlw   0xFF
    goto    tempo
    
;----------------------------------------------------------------------------
; Tempo with parameter (w)
;----------------------------------------------------------------------------
tempo:
    movwf   c1
tempo_1:
    movlw   0x04
    movwf   c2
tempo_2:
    decfsz  c2,f
    goto    tempo_2
    decfsz  c1,f
    goto    tempo_1
    return
    
    
;----------------------------------------------------------------------------
; End code
;----------------------------------------------------------------------------
END resetVec