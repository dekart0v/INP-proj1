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

 --signal cnt_inc  : std_logic;
 --signal cnt_dec  : std_logic;
 --signal cnt_out  : std_logic_vector(7  downto 0); -- ограничено 8 битами 

 type fsm_state is (init, fetch, decode, fsm_ptr_inc, fsm_ptr_dec, fsm_value_inc_read, fsm_value_inc_write, 
                    fsm_value_dec_read, fsm_value_dec_write, putchar, rtrn); -- fetch decode + ostalnyje FSM_STATE
 signal state   : fsm_state; -- RESET = 1 (to init the logics)
 signal state_2 : fsm_state; -- main

 --type instructions is (ptr_inc, ptr_dec, value_inc, value_dec, while_start, while_end, printf, getchar, break, rtrn); -- возможные значения переменной
 --signal instruction : instructions; -- переменная

 --signal filter : std_logic_vector(1 downto 0); --for mux "11" "00" "10" "01"

begin
 -- zde dopiste vlastni VHDL kod

 -- pri tvorbe kodu reflektujte rady ze cviceni INP, zejmena mejte na pameti, ze
 --   - nelze z vice procesu ovladat stejny signal,
 --   - je vhodne mit jeden proces pro popis jedne hardwarove komponenty, protoze pak
 --      - u synchronnich komponent obsahuje sensitivity list pouze CLK a RESET a
 --      - u kombinacnich komponent obsahuje sensitivity list vsechny ctene signaly.

    --DATA_ADDR <= ptr_out;
    --CODE_ADDR <= pc_out; -- инструкция X"00" например


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
  
  
    --CNT: process(CLK, RESET, cnt_inc, cnt_dec) -- 8bit restriction
    --begin
    --  if (RESET = '1') then cnt_out <= (others=>'0'); -- 0 потому что нужно вернуться в изначальное состояние
    --  elsif (CLK'event)and(CLK='1') then
    --    if (cnt_inc = '1') then cnt_out <= cnt_out + 1;
    --    elsif (cnt_dec = '1') then cnt_out <= cnt_out - 1;
    --    end if;
    --  end if;
    --end process;


    FSM_logic_start : process(CLK, RESET, EN, state_2)
    begin
      if (RESET = '1') then state <= init;
      elsif (EN = '1' and CLK'event and CLK = '1') then state <= state_2;
      end if;
    end process;
    
    
    FSM_logic : process(CLK, state, ptr_out, pc_out, OUT_BUSY, DATA_RDATA)
    begin
      pc_inc <= '0';
      pc_dec <= '0';
      ptr_inc <= '0';
      ptr_dec <= '0';
      DATA_EN <= '0';
      OUT_WREN <= '0';      

      -- тут прописать case state is when fetch; when decode; when >; when <; when +; when -; when .
      case state is
        when fetch => -- чтение из память[PC]
          CODE_ADDR <= pc_out;
          CODE_EN <= '1'; -- включаем rom
          state_2 <= decode;
        
        when decode => -- понять какая инструкция прочиталась 
          case CODE_DATA is 
            when X"3E" => state_2 <= fsm_ptr_inc;
            when X"3C" => state_2 <= fsm_ptr_dec;
            when X"2B" => state_2 <= fsm_value_inc_read;
            when X"2D" => state_2 <= fsm_value_dec_read;
            when X"2E" => state_2 <= putchar;
            when X"00" => state_2 <= rtrn;
            when others => state_2 <= rtrn; --TODO
          end case;
        
        when fsm_ptr_inc => 
          state_2 <= fetch;
          ptr_inc <= '1';
          pc_inc <= '1';

        when fsm_ptr_dec =>
          state_2 <= fetch;
          ptr_dec <= '1';
          pc_inc <= '1';

        when fsm_value_inc_read =>
          state_2 <= fsm_value_inc_write;
          DATA_ADDR <= ptr_out;
          DATA_EN <= '1';
          DATA_WREN <= '0'; 

        when fsm_value_inc_write =>
          state_2 <= fetch;
          pc_inc <= '1';
          DATA_EN <= '1';
          DATA_WREN <= '1';
          DATA_WDATA <= DATA_RDATA + 1;

        when fsm_value_dec_read =>
          state_2 <= fsm_value_dec_write;
          DATA_ADDR <= ptr_out;
          DATA_EN <= '1';
          DATA_WREN <= '0'; 

        when fsm_value_dec_write =>
          state_2 <= fetch;
          pc_inc <= '1';
          DATA_EN <= '1';
          DATA_WREN <= '1';
          DATA_WDATA <= DATA_RDATA - 1;

        when putchar =>
          if (OUT_BUSY = '1') then state_2 <= putchar;
          else 
            state_2 <= fetch;
            pc_inc <= '1';
            OUT_WREN <= '1';
            OUT_DATA <= DATA_RDATA;
          end if;

        when rtrn =>
          state_2 <= fetch;

        when others =>
          state_2 <= fetch;
          pc_inc <= '0';
        end case;
    end process;


end behavioral;