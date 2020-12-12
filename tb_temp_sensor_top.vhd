library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_temp_sensor_top is
end tb_temp_sensor_top;

architecture behavior of tb_temp_sensor_top is

    --Inputs
    signal sys_clk_i    : std_logic := '0';
    signal uart_din_emu : std_logic := '0';
    signal uart_rst_emu : std_logic := '0';

    --Outputs
    signal uart_dout_emu    : std_logic;
    signal s_br_clk_uart_o  : std_logic;
    signal uart_leds_emu    : std_logic_vector(7 downto 0);

    --i2c slave
    signal rst              : std_logic;
    signal read_req         : std_logic;
    signal data_to_master   : std_logic_vector(7 downto 0) := (others => '0');
    signal data_valid       : std_logic;
    signal data_from_master : std_logic_vector(7 downto 0);

    signal scl, sda : std_logic := 'H';     --'H' is to simulate Pull up resistors
    
    constant system_clock_period    : time := 20 ns;
    constant uart_clock_period      : time := 32 ns;    -- 29.5Mhz
    constant bit_period             : time := uart_clock_period*32; --921600bps
    
    type sample_array is array(natural range <>) of std_logic_vector(7 downto 0);

    constant test_data  : sample_array :=
    (
        --READ TDA7420 ID CMD -1: Write 0xB to I2C address 0x48
        x"00",        --BYTE1 
        x"10" ,       --BYTE2
        x"80"  ,      --BYTE3
        x"48",        --BYTE4
        x"00",        --BYTE5
        x"0B" ,       --BYTE6
        --READ ID CMD -2: Read from I2C
        x"00"  ,      --BYTE1 
        x"10"   ,     --BYTE2
        x"80" ,       --BYTE3
        x"C8" ,       --BYTE4
        x"00" ,       --BYTE5
        x"00" ,       --BYTE6
        --DUMMY for waiting 
        x"00"  ,      --BYTE1 
        x"20"   ,     --BYTE2
        x"00"  ,      --BYTE3
        x"00"    ,    --BYTE4
        x"00"    ,    --BYTE5
        x"00"    ,    --BYTE6
        --DUMMY for waiting
        x"00"     ,   --BYTE1 
        x"20"   ,     --BYTE2
        x"00"  ,      --BYTE3
        x"00" ,       --BYTE4
        x"00" ,       --BYTE5
        x"00"  ,      --BYTE6
        --Read registers to UART
        x"80"   ,     --BYTE1 
        x"00"  ,      --BYTE2
        x"00"   ,     --BYTE3
        x"00"    ,    --BYTE4
        x"00"    ,    --BYTE5
        x"00"    ,    --BYTE6
        --DUMMY for waiting
        x"00"     ,   --BYTE1 
        x"20"    ,    --BYTE2
        x"00"    ,    --BYTE3
        x"00"    ,    --BYTE4
        x"00"    ,    --BYTE5
        x"00"    ,    --BYTE6
        --DUMY for waiting
        x"00"     ,   --BYTE1 
        x"20"    ,    --BYTE2
        x"00"     ,   --BYTE3
        x"00"    ,    --BYTE4
        x"00"    ,    --BYTE5
        x"00"    ,    --BYTE6
        --Reset the ADC write 0x00 to ADT7420 register offset: 0x2F
        x"00"     ,   --BYTE1 
        x"10"      ,  --BYTE2
        x"C0"     ,   --BYTE3
        x"48"    ,    --BYTE4
        x"00"     ,   --BYTE5
        x"2F"     ,   --BYTE6
        --Write 0x80 to offset 0x03 to ADT740 to set 13bit
        x"00"      ,  --BYTE1 
        x"10"     ,   --BYTE2
        x"C0"     ,   --BYTE3
        x"48"     ,   --BYTE4
        x"80"      ,  --BYTE5
        x"03"       , --BYTE6
        --dummy
        x"00"  ,      --BYTE1 
        x"20"   ,     --BYTE2
        x"00"    ,    --BYTE3
        x"00"     ,   --BYTE4
        x"00"      ,  --BYTE5
        x"00"    ,    --BYTE6
        --Read two byte - 1 from I2C address 0x48
        x"00"     ,   --BYTE1 
        x"10"      ,  --BYTE2
        x"80"   ,     --BYTE3
        x"48" ,       --BYTE4
        x"00"  ,      --BYTE5
        x"00"    ,    --BYTE6
        --Read two byte - 2
        x"00" ,       --BYTE1 
        x"10"  ,      --BYTE2
        x"C0"   ,     --BYTE3
        x"C8"    ,    --BYTE4
        x"00"     ,   --BYTE5
        x"00"      ,  --BYTE6
        --dummy waiting
        x"00" ,       --BYTE1 
        x"20"  ,      --BYTE2
        x"00"   ,     --BYTE3
        x"00"    ,    --BYTE4
        x"00"     ,   --BYTE5
        x"00"      ,  --BYTE6
        --Read back from I2C
        x"80"   ,     --BYTE1 
        x"00"    ,    --BYTE2
        x"00"     ,   --BYTE3
        x"00"      ,  --BYTE4
        x"00"       , --BYTE5
        x"00"        --BYTE6
    );

begin

    --Instantiate the Unit Under Test (UUT)
    uut : entity work.temperature_sensor_top
        port map(
            SYS_CLK     => sys_clk_i,
            

            ADT7420_CT  => '0', --Not use
            ADT7420_INT => '0', --Not in use
            ADT7420_SCL => scl, --I2C SCL
            ADT7420_SDA => sda,  --I2C SDA 
        
            USER_LED    => uart_leds_emu,

            GPIO_J3_39  => uart_dout_emu,
            GPIO_J3_40  => uart_din_emu
        );

    i2c_minion: entity work.I2C_minion
        generic map(
            MINION_ADDR     => "1001000"
        )
        port map(
            scl             => scl,
            sdc             => sda,
            clk             => sys_clk_i,
            rst             => rst,

            --User Interface
            read_req        => read_req,
            data_to_master  => data_to_master,
            data_valid      => data_valid,
            data_from_master    => data_from_master
        );

    scl <= 'H';
    sda <= 'H';

    s_br_clk_uart_o <= << signal 
    .tb_temp_sensor_top.uut.uartTOi2c_pm.s_uart_br_clk : std_logic >>;

    i2c_data : process(sys_clk_i)
    begin
        if (rising_edge(sys_clk_i)) then
            if read_req = '1'  then         --the read back value increment by one every read
                data_to_master <= std_logic_vector(unsigned(data_to_master) + 1);
            end if ;
        end if ;
    end process;

    uart_clock : process
    begin
        sys_clk_i <= '0';
        wait for system_clock_period / 2;
        sys_clk_i <= '1';
        wait for system_clock_period / 2;
    end process;

    rst_p : process
    begin
        rst <= '1';
        wait for 200 ns;
        wait until rising_edge(sys_clk_i);
        rst <= '0';
        wait;
    end process;

    --Stimulus process
    stim_proc : process
    begin

        --hold reset
        wait  for 50 ns;
        wait for system_clock_period*10;
        -- insert stimulus here
        uart_din_emu    <= '1';

        wait for 10 us;

        --look through test_data
        for j in test_data'range loop
            --tx_start_bit
            uart_din_emu <= '0';
            wait for bit_period;

            --Byte serializer
            for i in 0 to 7 loop
                uart_din_emu <= test_data(j)(i);
                wait for bit_period;
            end loop;

            --tx_stop_bit
            uart_din_emu <= '1';
            wait for bit_period;
            wait for 5 us;
        end loop;

        wait;
    end process;

end architecture behavior ; 