-- cpu.vhd: Simple 8-bit CPU (BrainLove interpreter)
-- Copyright (C) 2021 Brno University of Technology,
--                    Faculty of Information Technology
-- Author(s): Iudenkov Ilia  (xiuden00 AT stud.fit.vutbr.cz)
--            Zdenek Vasicek (xvasic11 AT stud.fit.vutbr.cz)
--

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

-- ----------------------------------------------------------------------------
--                        Entity declaration
-- ----------------------------------------------------------------------------
entity cpu is
 port (
   CLK   : in std_logic;  -- hodinovy signal
   RESET : in std_logic;  -- asynchronni reset procesoru
   EN    : in std_logic;  -- povoleni cinnosti procesoru
 
   -- synchronni pamet ROM
   CODE_ADDR : out std_logic_vector(11 downto 0); -- adresa do pameti ()
   CODE_DATA : in std_logic_vector(7 downto 0);   -- CODE_DATA <- rom[CODE_ADDR] pokud CODE_EN='1' (сама Brainfuck инструкция)
   CODE_EN   : out std_logic;                     -- povoleni cinnosti
   
   -- synchronni pamet RAM
   DATA_ADDR  : out std_logic_vector(9 downto 0); -- adresa do pameti
   DATA_WDATA : out std_logic_vector(7 downto 0); -- ram[DATA_ADDR] <- DATA_WDATA pokud DATA_EN='1'
   DATA_RDATA : in std_logic_vector(7 downto 0);  -- DATA_RDATA <- ram[DATA_ADDR] pokud DATA_EN='1'
   DATA_WREN  : out std_logic;                    -- cteni z pameti (DATA_WREN='0') / zapis do pameti (DATA_WREN='1')
   DATA_EN    : out std_logic;                    -- povoleni cinnosti
   
   -- vstupni port
   IN_DATA   : in std_logic_vector(7 downto 0);   -- IN_DATA obsahuje stisknuty znak klavesnice pokud IN_VLD='1' a IN_REQ='1'
   IN_VLD    : in std_logic;                      -- data platna pokud IN_VLD='1'
   IN_REQ    : out std_logic;                     -- pozadavek na vstup dat z klavesnice
   
   -- vystupni port
   OUT_DATA : out std_logic_vector(7 downto 0);   -- zapisovana data
   OUT_BUSY : in std_logic;                       -- pokud OUT_BUSY='1', LCD je zaneprazdnen, nelze zapisovat,  OUT_WREN musi byt '0'
   OUT_WREN : out std_logic                       -- LCD <- OUT_DATA pokud OUT_WE='1' a OUT_BUSY='0'
 );
end cpu;


-- ----------------------------------------------------------------------------
--                      Architecture declaration
-- ----------------------------------------------------------------------------
architecture behavioral of cpu is -- main

 -- zde dopiste potrebne deklarace signalu
 signal pc_inc   : std_logic;
 signal pc_dec   : std_logic;
 signal pc_out   : std_logic_vector(11 downto 0); -- 12 byte ROM

 signal ptr_inc  : std_logic;
 signal ptr_dec  : std_logic;
 signal ptr_out  : std_logic_vector(9  downto 0); -- 10 byte RAM

 type fsm_state is (init, fetch, decode, fsm_ptr_inc, fsm_ptr_dec, fsm_value_inc_read, fsm_value_inc_write, 
                    fsm_value_dec_read, fsm_value_dec_write, putchar, rtrn, skip); -- states of CPU
 signal state   : fsm_state; -- after RESET = 1 (to init the logics)
 signal state_2 : fsm_state; -- so CPU knows which state is coming next

begin

    PC: process(CLK, RESET, pc_inc, pc_dec) -- Program Counter
    begin
      if (RESET = '1') then pc_out <= (others=>'0');       -- PC_OUT = 0 after RESET
      elsif (CLK'event)and(CLK='1') then                   -- rising edge
        if (pc_inc = '1') then pc_out <= pc_out + 1;       -- PC_INC
        elsif (pc_dec = '1') then pc_out <= pc_out - 1;    -- PC_DEC
        end if;
      end if;
    end process;


    PTR: process(CLK, RESET, ptr_inc, ptr_dec) -- Pointer to RAM
    begin
      if (RESET = '1') then ptr_out <= (others=>'0');      -- PTR_OUT = 0 after RESET
      elsif (CLK'event)and(CLK='1') then                   -- rising edge
        if (ptr_inc = '1') then ptr_out <= ptr_out + 1;    -- PTR_INC
        elsif (ptr_dec = '1') then ptr_out <= ptr_out - 1; -- PTR_DEC
        end if;
      end if;
    end process;
  
  
    FSM_logic_start : process(CLK, RESET, EN, state_2) -- present state logic
    begin
      if (RESET = '1') then state <= init;                                -- present state after reset
      elsif (EN = '1' and CLK'event and CLK = '1') then state <= state_2; -- next state after present state + rising edge
      end if;
    end process;
    
    
    FSM_logic : process(CLK, state, ptr_out, pc_out, OUT_BUSY, DATA_RDATA) -- next state logic
    begin
      pc_inc <= '0';   --|>
      pc_dec <= '0';   --|> {declaring initial values
      ptr_inc <= '0';  --|> after present state (RESET = 1)}
      ptr_dec <= '0';  --|>
      DATA_EN <= '0';  -- RAM OFF
      OUT_WREN <= '0'; -- without this declared prints the last char endlessly

      case state is -- the logic itself

        when fetch => -- ROM[pc_out]: contains instruction
          CODE_ADDR <= pc_out;            -- CODE_DATA now has the instruction
          CODE_EN <= '1';                 -- ROM ON
          state_2 <= decode;              -- defining the next state
        
        when decode => -- convert instruction into fsm_state function
          case CODE_DATA is 
            when X"3E"  => state_2 <= fsm_ptr_inc;        -- >
            when X"3C"  => state_2 <= fsm_ptr_dec;        -- <
            when X"2B"  => state_2 <= fsm_value_inc_read; -- +
            when X"2D"  => state_2 <= fsm_value_dec_read; -- -
            when X"2E"  => state_2 <= putchar;            -- .
            when X"00"  => state_2 <= rtrn;               -- NULL
            when others => state_2 <= skip;               -- non-brainfuck instructions
          end case;
        
        when fsm_ptr_inc => -- {>}
          state_2 <= fetch;               -- defining the next state
          ptr_inc <= '1';                 -- >
          pc_inc <= '1';                  -- changing to next Brainfuck instruction

        when fsm_ptr_dec => -- {<}
          state_2 <= fetch;               -- defining the next state
          ptr_dec <= '1';                 -- <
          pc_inc <= '1';                  -- changing to next Brainfuck instruction

        when fsm_value_inc_read => -- 1st part (reading) of {+}
          state_2 <= fsm_value_inc_write; -- defining the next state (second part of the function; we cant read and write in a single one)
          DATA_ADDR <= ptr_out;           -- getting the address from ptr_out and writing it to the DATA_ADDR
          DATA_EN <= '1';                 -- RAM ON
          DATA_WREN <= '0';               -- RAM read

        when fsm_value_inc_write => -- 2nd part (writing) of {+}
          state_2 <= fetch;               -- defining the next state
          pc_inc <= '1';                  -- changing to next Brainfuck instruction
          DATA_EN <= '1';                 -- to be able to generate output; RAM ON
          DATA_WREN <= '1';               -- to be able to generate output; RAM write
          DATA_WDATA <= DATA_RDATA + 1;   -- the output itself + 1

        when fsm_value_dec_read => -- 1st part (reading) of {-}
          state_2 <= fsm_value_dec_write; -- defining the next state (second part of the function; we cant read and write in a single one)
          DATA_ADDR <= ptr_out;           -- getting the address from ptr_out and writing it to the DATA_ADDR
          DATA_EN <= '1';                 -- RAM ON
          DATA_WREN <= '0';               -- RAM read

        when fsm_value_dec_write => -- 2nd part (writing) of {-}
          state_2 <= fetch;               -- defining the next state
          pc_inc <= '1';                  -- changing to next Brainfuck instruction
          DATA_EN <= '1';                 -- to be able to generate output; RAM ON
          DATA_WREN <= '1';               -- to be able to generate output; RAM write
          DATA_WDATA <= DATA_RDATA - 1;   -- the output itself - 1

        when putchar => -- {.} print char on the display
          if (OUT_BUSY = '1') then state_2 <= putchar; -- if output has smth already, we repeat the state
          else 
            state_2 <= fetch;             -- defining the next state
            pc_inc <= '1';                -- changing to next Brainfuck instruction
            OUT_WREN <= '1';              -- allowing to print smth on the LCD
            OUT_DATA <= DATA_RDATA;       -- printing out what we have in DATA_RDATA after *write() functions
          end if;

        when rtrn => -- halt the CPU
          state_2 <= rtrn;                -- defining the next state (return has return as the next state, so it will stop eventually)

        when skip => -- skipping non-brainfuck characters/insctuctions
          state_2 <= fetch;               -- defining the next state (skip the undefined Brainfuck instruction and go fetch next instead)
          pc_inc <= '1';                  -- changing to next Brainfuck instruction

        when others => -- just catch some random stuff (no idea what exactly, since we already have skip(), but we stiil need 'others' clause to compile correctly)
          state_2 <= fetch;               -- defining the next state (skip the undefined Brainfuck instruction and go fetch next instead)
          pc_inc <= '0';                  -- NOT changing to next Brainfuck instruction

        end case;
    end process;


end behavioral;