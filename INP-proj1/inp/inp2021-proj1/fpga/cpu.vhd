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
   OUT_DATA : out  std_logic_vector(7 downto 0);  -- zapisovana data
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

 signal cnt_inc  : std_logic;
 signal cnt_dec  : std_logic;
 signal cnt_out  : std_logic_vector(7  downto 0); -- ограничено 8 битами 

 type fsm_state is (init, fetch, decode, fsm_ptr_inc_read, fsm_ptr_inc_write, fsm_ptr_dec, fsm_value_inc, fsm_value_dec_read,
                    fsm_value_dec_write, fsm_while_start, fsm_while_end, fsm_printf, fsm_getchar, fsm_break, fsm_rtrn); -- fetch decode + ostalnyje FSM_STATE
 signal state : fsm_state;

 type instructions is (ptr_inc, ptr_dec, value_inc, value_dec, while_start, while_end, printf, getchar, break, rtrn); -- возможные значения переменной
 signal instruction : instructions; -- переменная

 signal filter : std_logic_vector(1 downto 0); --for mux

begin
 -- zde dopiste vlastni VHDL kod

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

    PC: process(CLK, RESET, pc_inc, pc_dec) -- Program Counter (тут хранится id инструкции следующей)
    begin
      if (RESET = '1') then pc_out <= (others=>'0'); -- 0 потому что нужно вернуться в изначальное состояние
      elsif (CLK'event)and(CLK='1') then
        if (pc_inc = '1') then pc_out <= pc_out + 1;   -- PC_INC
        elsif (pc_dec = '1') then pc_out <= pc_out - 1; -- PC_DEC
        end if;
      end if;
    end process;


    PTR: process(CLK, RESET, ptr_inc, ptr_dec) -- Pointer to RAM
    begin
      if (RESET = '1') then ptr_out <= (others=>'0'); -- 0 потому что нужно вернуться в изначальное состояние
      elsif (CLK'event)and(CLK='1') then
        if (ptr_inc = '1') then ptr_out <= ptr_out + 1;
        elsif (ptr_dec = '1') then ptr_out <= ptr_out - 1;
        end if;
      end if;
    end process;
    DATA_ADDR <= ptr_out;
  
  
    CNT: process(CLK, RESET, cnt_inc, cnt_dec) -- 8bit restriction
    begin
      if (RESET = '1') then cnt_out <= (others=>'0'); -- 0 потому что нужно вернуться в изначальное состояние
      elsif (CLK'event)and(CLK='1') then
        if (cnt_inc = '1') then cnt_out <= cnt_out + 1;
        elsif (cnt_dec = '1') then cnt_out <= cnt_out - 1;
        end if;
      end if;
    end process;
  

    DECODE: process(CODE_DATA) -- значению переменной инструкции дается один из возмодный варинатов из instructions
    begin
      case CODE_DATA is
        when X"3E" => instruction <= ptr_inc;       -- >
        when X"3C" => instruction <= ptr_dec;       -- <
        when X"2B" => instruction <= value_inc;     -- +
        when X"2D" => instruction <= value_dec;     -- -
        when X"5B" => instruction <= while_start;   -- [
        when X"5D" => instruction <= while_end;     -- ]
        when X"2E" => instruction <= printf;        -- .
        when X"2C" => instruction <= getchar;       -- ,
        when X"7E" => instruction <= break;         -- ~
        when X"00" => instruction <= rtrn;          -- NULL
        end case; -- еще добавить если у нас что-то другое чтобы выходило нахуй
    end process;
  
    
    MULTIPLEXOR : process(CLK, filter, IN_DATA, DATA_RDATA) -- хз нахуй надо
    begin
      case filter is
        when "00" => DATA_WDATA <= IN_DATA; -- запись инпута
        when "01" => DATA_WDATA <= DATA_RDATA + '1'; -- запись +1
        when "10" => DATA_WDATA <= DATA_RDATA - '1'; -- запись -1
        when "11" => DATA_WDATA <= X"00";
      end case;
    end process;


    FSM_STATE : process (CLK, RESET, EN, CODE_DATA, IN_VLD, IN_DATA, DATA_RDATA, OUT_BUSY, state, instruction, cnt_out, filter)
    begin
      if (RESET = "1") then state <= init;
      elsif (CLK'event) and (CLK = '1') then  -- нужен второй автомат
        if (EN = "1") then
          state <= init;
          CODE_EN    <= '1';
          DATA_EN    <= '0';
          DATE_WREN  <= '0';
          IN_REQ     <= '0';
          OUT_WE     <= '0';
          pc_inc     <= '0';
          pc_dec     <= '0';
          ptr_inc    <= '0';
          ptr_dec    <= '0';
          cnt_inc    <= '0';
          cnt_dec    <= '0';
          filter     <= "00";

          case state is
            when init => state <= fetch;

            when fetch => state <= decode; 
              CODE_EN <= '1';
            
            when decode =>
              case instruction is
                when ptr_inc      => state <= fsm_ptr_inc;
                when ptr_dec      => state <= fsm_ptr_dec;
                when value_inc    => state <= fsm_value_inc;
                when value_dec    => state <= fsm_value_dec;
                when while_start  => state <= fsm_while_start;
                when while_end    => state <= fsm_while_end;
                when printf       => state <= fsm_printf;
                when getchar      => state <= fsm_getchar;
                when break        => state <= fsm_break;
                when rtrn         => state <= fsm_rtrn;
              end case;
              
            when fsm_ptr_inc =>
                state   <= fetch;
                ptr_inc <= '1';
                pc_inc  <= '1';

            when fsm_ptr_dec =>
                state   <= fetch;
                ptr_dec <= '1';
                pc_inc  <= '1';

            when fsm_value_inc_read =>
                state <= fsm_value_inc_write;
                DATA_WREN <= '0';
                DATA_EN <= '1';

            when fsm_value_inc_write =>
                state <= fetch;
                DATA_EN <= '1';
                DATA_WREN <= '1';
                pc_inc <= '1';
                filter <= "01"; -- записать инпут + 1

            when fsm_value_dec_read =>
                state <= fsm_value_dec_write;
                DATA_WREN <= '0';
                DATA_EN <= '1';

            when fsm_value_dec_write =>
                state <= fetch;
                DATA_EN <= '1';
                DATA_WREN <= '1';
                pc_inc <= '1';
                filter <= "10"; -- записать инпут -1

            --when fsm_while_start =>
                
            --when fsm_while_end =>

            when fsm_printf =>
                if (OUT_BUSY = '1') then state <= fsm_printf;
                else
                  state <= fetch;
                  OUT_DATA <= DATA_RDATA;
                  DATA_WREN <= '0';
                  OUT_WREN <= '1';
                  pc_inc <= '1';
                end if;

            when fsm_getchar =>
                state <= fsm_getchar;
                IN_REQ <= '1';
                if (IN_VLD = '1') then
                  state <= fetch;
                  DATA_EN <= '1';
                  DATA_WREN <= '1';
                  pc_inc <= '1';
                  IN_REQ <= '0';
                  filter <= "00"; -- запись инпута
                end if;

            --when fsm_break        =>

            when fsm_rtrn => state <= fsm_rtrn;
                  
          end case;
        end if;
      end if;
    end process;


end behavioral;