library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity uartTOi2c is
  port (
    clk_uart_29MHz_i    : in std_logic;
    uart_rst_i          : in std_logic;
    uart_leds_o         : out std_logic_vector(7 downto 0);
    clk_uart_monitor_o  : out std_logic;

    -----------UART TX & RX----------------
    uart_dout_o         : out std_logic;
    uart_din_i          : in std_logic;

    -----------I2C interface--------------
    i2c_scl             : inout std_logic;  --serial clock
    i2c_dat             : inout std_logic  --seria data
  ) ;
end entity uartTOi2c;

architecture rtl of uartTOi2c is

    signal s_rst       : std_logic;    --main reset
    signal s_clk_uart   : std_logic;  --slow (29MHz) clock
    --uart control signals
    signal s_uart_br_clk            : std_logic; --unused clock monitor
    signal s_uart_rx_add            : std_logic_vector(15 downto 0);
    signal s_uart_rx_data           : std_logic_vector(31 downto 0);
    signal s_uart_rx_rdy            : std_logic;
    signal s_uart_rx_stb_read_data  : std_logic;
    signal s_update                 : std_logic;
    signal s_uart_tx_add            : std_logic_vector(15 downto 0);
    signal s_uart_tx_data           : std_logic_vector(31 downto 0);
    signal s_uart_tx_data_rdy       : std_logic;
    signal s_uart_tx_req            : std_logic;
    signal s_uart_tx_stb_acq        : std_logic;
    signal s_tx_complete            : std_logic;
    -- address decoder signals
    signal r_config_addr_uart       : std_logic_vector(1 downto 0);
    signal r_leds                   : std_logic_vector(7 downto 0); --0x0000
    signal reg01                    : std_logic_vector(31 downto 0);--00010
    signal reg02                    : std_logic_vector(31 downto 0);--00001
    ------------------------------------------------
    --signals for i2c Master block --
    ------------------------------------------------
    signal s_rst_n      : std_logic;
    signal i2c_busy     : std_logic;
    signal i2c_busy_dly : std_logic;
    signal i2c_busy_01  : std_logic; -- rising edge for i2c_busy
    signal i2cByte1     : std_logic;
    signal i2c_2bytes   : std_logic;
    signal data_wr      : std_logic_vector(7 downto 0);
    signal data_rd      : std_logic_vector(7 downto 0);
    -------------------------------------------------
    -- State Machine states--
    -------------------------------------------------
    type t_tx_reg_map is (IDLE, WAIT_A_BYTE, LATCH, TRANSMIT);
    signal s_tx_fsm     : t_tx_reg_map;

begin

    s_rst   <= not uart_rst_i;  --Change to active hight reset
    s_rst_n <= uart_rst_i;      --active low reset
    uart_leds_o <= not r_leds;  --Output LED with '1' mean on 
    s_clk_uart          <= clk_uart_29MHz_i;    --UART system clock 29.4912 MHz
    clk_uart_monitor_o  <= s_uart_br_clk;       
    i2c_busy_01 <= i2c_busy and not i2c_busy_dly;
    i2c_2bytes  <= reg01(30);   --This i2c command has 2 bytes  
    --Data write to the I2C Master depends on # of bytes operation
    data_wr <= reg01(7 downto 0) when i2cByte1 = '0' else reg01(15 downto 8);
    
    --UART simple register map : UART to BeMicro MAX10
    register_map : process(s_rst, s_clk_uart)
    begin
        if s_rst = '1' then         --reset all registers here
            s_uart_rx_stb_read_data <= '0';
            s_update                <= '0';
            r_leds                  <= (others => '0');
            r_config_addr_uart      <= "10";
            reg01                   <= (others => '0');
            i2c_busy_dly            <= '0';
            i2cByte1                <= '0';
        elsif rising_edge(s_clk_uart) then
            i2c_busy_dly <= i2c_busy;
            if s_uart_rx_rdy = '1' then
                case( s_uart_rx_add ) is
                
                    when x"0000" => r_leds  <= s_uart_rx_data(7 downto 0);
                    when x"0010" => reg01   <= s_uart_rx_data;
                    when x"8000" => s_update <= '1';    --register update self clearing  
                    when others => null;
                end case ;
                
                s_uart_rx_stb_read_data <= '1';
            else
                s_uart_rx_stb_read_data <= '0';
                s_update                <= '0'; --register update self clearing

                --Last byte send out to the i2c Master, then clean up data bits
                if(i2c_busy_01 = '1' and i2cByte1 = '0'  and i2c_2bytes = '0' ) then
                    reg01(29 downto 0)  <= (others => '0');
                end if;

                --After send the command to the I2C Master, then clean up command bits 
                if (i2c_busy_01 = '1' and (i2cByte1 = i2c_2bytes)) then     --11 or 00 condition
                reg01(31 downto 30) <= (others => '0');
                end if ;

                if (s_uart_rx_stb_read_data = '1') then
                    i2cByte1    <= '0';     --reset the condition after UART read request
                elsif (i2c_2bytes = '1' and i2c_busy_01 = '1') then
                    --Toggle every time i2c_busy change from low to high and two bytes operations
                    i2cByte1 <= not i2cByte1;
                end if ;
            end if ;
        end if ;
    end process;

    i2c_data_p : process( s_rst, s_clk_uart )
    begin
        if s_rst = '1' then
            reg02(29 downto 0) <= (others => '0');
        elsif rising_edge(s_clk_uart)  then
            --when the busy is changed from 1 to 0
            if (i2c_busy = '0' and i2c_busy_dly = '1') then
                --copy the I2C data_rd to reg02(7 downto 0)
                --and copy reg02(7 downto 0) to reg02(15 downto 0)
                reg02(15 downto 0) <= reg02(7 downto 0) & data_rd;
            end if ;
            --bit 15 to 3 is the 13 bit temperature
            --each 1 equal 0.0625 and 0x0 equal to 0°C
            --Only need bit 15 to 7 to read out in integer
            --shift bits to upper bytes for easy read in degree C
            reg02(24 downto 16) <= reg02(15 downto 7);  

        end if ;
    end process ;
    
    register_update : process(s_rst, s_clk_uart)
    variable v_uart_tx_add  : unsigned(15 downto 0);
    variable v_count        : unsigned(15 downto 0);
    begin

        if s_rst = '1' then             --reset all registers here
            s_uart_tx_data_rdy  <= '0';
            s_uart_tx_req       <= '0';
            v_uart_tx_add       := (others => '0');
            v_count             := (others => '0');
            s_uart_tx_data      <= (others => '0');
            s_uart_tx_add       <= (others => '0');
            s_tx_fsm            <= IDLE;
    
        elsif rising_edge(s_clk_uart) then
            case( s_tx_fsm ) is
            
                when IDLE =>
                    if s_update = '1' then
                        s_tx_fsm <= WAIT_A_BYTE;
                    else
                        s_uart_tx_data_rdy  <= '0';
                        s_uart_tx_req       <= '0';
                        v_uart_tx_add       := (others => '0');
                        v_count             := (others => '0');
                        s_uart_tx_data      <= (others => '0');
                        s_uart_tx_add       <= (others => '0');
                        s_tx_fsm            <= IDLE;
                    end if ;
                
                when WAIT_A_BYTE =>
                    s_uart_tx_data_rdy   <= '0';
                    v_count              := v_count + 1;
                    if v_count = x"0900" then
                        v_uart_tx_add   := v_uart_tx_add + 1;
                        s_tx_fsm        <= LATCH; 
                    else
                        s_tx_fsm        <= WAIT_A_BYTE;    
                    end if ;
                
                when LATCH  =>
                    if s_uart_tx_stb_acq = '0' then
                        s_uart_tx_req   <= '1';
                        s_uart_tx_add   <= std_logic_vector(v_uart_tx_add);

                        case(v_uart_tx_add) is
                            
                            when x"0001" => s_uart_tx_data(7 downto 0) <= r_ledds;
                                            s_tx_fsm    <= TRANSMIT;
                            when x"0010" => s_uart_tx_data <= reg01;
                                            s_tx_fsm    <= TRANSMIT;
                            when x"0011" => s_uart_tx_data <= reg02;
                                            s_tx_fsm    <= TRANSMIT;
                            --End of Transmission register = last register + 1
                            when x"0012" => s_tx_fsm    <= IDLE;  --end of transmission
                            when others =>  s_uart_tx_data      <= (others => '0');
                                            v_uart_tx_add       := v_uart_tx_add + 1;
                                            s_uart_tx_data_rdy  <= '0';  
                                            s_tx_fsm            <= LATCH;
                        end case ;
                    else
                        v_count     := (others => '0');
                         s_tx_fsm    <= WAIT_A_BYTE;
                    end if ;

                when TRANSMIT =>
                    s_uart_tx_data_rdy  <= '1';
                    v_count             := (others => '0');
                    s_tx_fsm            <= WAIT_A_BYTE;

                when others =>
                    s_tx_fsm    <= IDLE;
            end case ;
        end if ;
    end process ;
    
    uart_wrapper : entity work.uart_16550_wrapper
        port map(
            -- general purpose
            sys_clk_i               =>    s_clk_uart,   -- system clock
            sys_rst_i               =>    s_rst,        -- system reset
            -- TX/RX process command line
            echo_en_i               =>    r_config_addr_uart(0),    -- Echo enable (byte by byte) enable/disable = 1/0
            tx_addr_wwo_i	        =>    r_config_addr_uart(1),    -- control of TX process With or WithOut address W/WO=(1/0)
            -- serial I/O side
            uart_din_i              =>    uart_din_i, 	        -- Serial data INPUT signal (from the FPGA)
            uart_dout_o             =>    uart_dout_o,  	    -- Serial data OUTPUT signal (to the FPGA)
            -- parallel I/O side
            s_br_clk_uart_o         =>    s_uart_br_clk,  		-- br_clk clock probe signal
            -- RX part/control
            v_rx_add_o	            =>    s_uart_rx_add,	    -- 16 bits full addr ram input
            v_rx_data_o	            =>    s_uart_rx_data,  	    -- 32 bits full data ram input
            s_rx_rdy_o	            =>    s_uart_rx_rdy,  		-- add/data ready to be write into RAM
            s_rx_stb_read_data_i    => s_uart_rx_stb_read_data,	-- strobe signal from RAM ... 
            -- TX part/control
            s_tx_proc_rqst_i        => s_uart_tx_req,	    -- stream TX process request 1/0 tx enable/disable
            v_tx_add_ram_i          => s_uart_tx_add,		-- 16 bits full addr ram output
            v_tx_data_ram_i			=> s_uart_tx_data,      -- 32 bits full data ram output
            s_tx_ram_data_rdy_i		=> s_uart_tx_data_rdy,	-- ram output data ready and stable
            s_tx_stb_ram_data_acq_o => s_uart_tx_stb_acq	-- strobe ram data/address output acquired 1/0 acquired/not acquired
        );

    i2c_p : entity work.i2c_master
        generic map(
            input_clk   => 29_491_200,  --input clock speed from user logic in Hz
            bus_clk     => 100_000      --speed the i2c bus (scl) will run at in Hz
        )
        port map(
            clk       =>    s_clk_uart,             --system clock
            reset_n   =>    s_rst_n,                --active low reset
            ena       =>    reg01(31),              --latch in command
            addr      =>    reg01(22 downto 16),    --address of target slave
            rw        =>    reg01(23),              --'0' is write, '1' is read
            data_wr   =>    data_wr,                --data to write to slave
            busy      =>    i2c_busy,               --indicates transaction in progress
            data_rd   =>    data_rd,                --data read from slave
            ack_error =>    reg02(30),              --flag if improper acknowledge from slave
            sda       =>    i2c_dat,                --serial data output of i2c bus
            scl       =>    i2c_scl                 --serial clock output of i2c bus
        );
    


end architecture rtl ; 