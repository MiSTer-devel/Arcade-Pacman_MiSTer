//============================================================================
//  MAME hiscore.dat support for MiSTer arcade cores.
//
//  https://github.com/JimmyStones/Hiscores_MiSTer
//
//  Copyright (c) 2021 Alan Steremberg
//  Copyright (c) 2021 Jim Gregory
//
//  This program is free software; you can redistribute it and/or modify it
//  under the terms of the GNU General Public License as published by the Free
//  Software Foundation; either version 3 of the License, or (at your option)
//  any later version.
//
//  This program is distributed in the hope that it will be useful, but WITHOUT
//  ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
//  FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
//  more details.
//
//  You should have received a copy of the GNU General Public License along
//  with this program; if not, write to the Free Software Foundation, Inc.,
//  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
//============================================================================
/*
 Version history:
 0001 - 2021-03-06 -    First marked release
 0002 - 2021-03-06 -    Added HS_DUMPFORMAT localparam to identify dump version (for future use)
                            Add HS_CONFIGINDEX and HS_DUMPINDEX parameters to configure ioctl_indexes
 0003 - 2021-03-10 -    Added WRITE_REPEATCOUNT and WRITE_REPEATDELAY to handle tricky write situations
============================================================================
*/

module hiscore
#(
    parameter HS_ADDRESSWIDTH=10,                           // Max size of game RAM address for highscores
    parameter HS_CONFIGINDEX=3,                         // ioctl_index for config transfer
    parameter HS_DUMPINDEX=4,                               // ioctl_index for dump transfer
    parameter CFG_ADDRESSWIDTH=4,                           // Max size of RAM address for highscore.dat entries (default 4 = 16 entries max)
    parameter CFG_LENGTHWIDTH=1,                            // Max size of length for each highscore.dat entries (default 1 byte = 255)
    parameter DELAY_CHECKWAIT=6'b111111,                // Delay between start/end check attempts
    parameter DELAY_CHECKHOLD=3'b111,               // Hold time for start/end check reads (allows mux to settle)
    parameter WRITE_REPEATCOUNT=8'b1,                   // Number of times to write score to game RAM
    parameter WRITE_REPEATDELAY=31'b1111                // Delay between subsequent write attempts to game RAM
)
(
    input          clk,
    input          reset,
    input   [31:0] delay,          // Custom initial delay before highscore load begins

    input          ioctl_upload,
    input          ioctl_download,
    input          ioctl_wr,
    input   [24:0] ioctl_addr,
    input   [7:0]  ioctl_dout,
    input   [7:0]  ioctl_din,
    input   [7:0]  ioctl_index,

    output  [HS_ADDRESSWIDTH-1:0]  ram_address,    // Address in game RAM to read/write score data
    output  [7:0]                  data_to_ram,    // Data to write to game RAM
    output  reg                    ram_write,      // Write to game RAM (active high)
    output  reg                    ram_access      // RAM read or write required (active high)
);

/*
Hiscore config structure (CFG_LENGTHWIDTH=1)
------------------------
00 00 43 0b  0f    10  01  00
00 00 40 23  02    04  12  00
[   ADDR  ] LEN START END PAD

4 bytes     Address of ram entry (in core memory map)
1 byte      Length of ram entry in bytes
1 byte      Start value to check for at start of address range before proceeding
1 byte      End value to check for at end of address range before proceeding
1 byte      (padding)


Hiscore config structure (CFG_LENGTHWIDTH=2)
------------------------
00 00 43 0b  00 0f    10  01
00 00 40 23  00 02    04  12
[   ADDR  ] [LEN ] START END

4 bytes     Address of ram entry (in core memory map)
2 bytes     Length of ram entry in bytes
1 byte      Start value to check for at start of address range before proceeding
1 byte      End value to check for at end of address range before proceeding

*/

localparam HS_DUMPFORMAT=1; // Version identifier for dump format

// HS_DUMPFORMAT = 1 --> No header, just the extracted hiscore data


// Hiscore config and dump status
reg       downloading_config;
reg       downloading_dump;
reg       uploading_dump;
reg       downloaded_config = 1'b0;
reg       downloaded_dump = 1'b0;
reg       uploaded_dump = 1'b0;
reg [3:0] initialised;

assign downloading_config = ioctl_download && (ioctl_index==HS_CONFIGINDEX);
assign downloading_dump = ioctl_download && (ioctl_index==HS_DUMPINDEX);
assign uploading_dump = ioctl_upload && (ioctl_index==HS_DUMPINDEX);

// Delay constants
reg [31:0] delay_default = 24'hFFFF;                            // Default initial delay before highscore load begins (overridden by delay from module inputs if supplied)
reg [31:0] read_defaultwait = DELAY_CHECKWAIT;          // Delay between start/end check attempts
reg [31:0] read_defaultcheck = DELAY_CHECKHOLD;         // Duration of start/end check attempt (>1 loop to allow pause/mux based access to settle)

assign ram_address = ram_addr[HS_ADDRESSWIDTH-1:0];

reg [3:0]                       state = 4'b0000;            // Current state machine index
reg [3:0]                       next_state = 4'b0000;   // Next state machine index to move to after wait timer expires
reg [31:0]                      wait_timer;                 // Wait timer for inital/read/write delays
reg                             ram_read = 1'b0;            // Is RAM actively being read

reg [CFG_ADDRESSWIDTH-1:0]      counter = 1'b0;         // Index for current config table entry
reg [CFG_ADDRESSWIDTH-1:0]      total_entries=1'b0;     // Total count of config table entries
reg                             reset_last = 1'b0;      // Last cycle reset
reg [7:0]                       write_counter = 1'b0;   // Index of current game RAM write attempt

reg [7:0]                       last_ioctl_index;           // Last cycle HPS IO index
reg                             last_ioctl_download=0;  // Last cycle HPS IO download
reg                             last_ioctl_upload=0;        // Last cycle HPS IO upload

reg  [24:0]                     ram_addr;                   // Target RAM address for hiscore read/write
reg  [24:0]                     old_io_addr;
reg  [24:0]                     base_io_addr;
wire [23:0]                     addr_base;
reg  [24:0]                     end_addr;
reg  [24:0]                     local_addr;
wire [(CFG_LENGTHWIDTH*8)-1:0]  length;
wire [7:0]                      start_val;
wire [7:0]                      end_val;

wire address_we = downloading_config & (ioctl_addr[2:0] == 3'd3);
wire length_we = downloading_config & (ioctl_addr[2:0] == 3'd3 + CFG_LENGTHWIDTH);
wire startdata_we = downloading_config & (ioctl_addr[2:0] == 3'd4 + CFG_LENGTHWIDTH);
wire enddata_we = downloading_config & (ioctl_addr[2:0] == 3'd5 + CFG_LENGTHWIDTH);

wire [23:0]                     address_data_in = {address_data_b3, address_data_b2, ioctl_dout};
wire [(CFG_LENGTHWIDTH*8)-1:0]  length_data_in = (CFG_LENGTHWIDTH == 1'b1) ? ioctl_dout : {length_data_b2, ioctl_dout};
reg [7:0]                       address_data_b3;
reg [7:0]                       address_data_b2;
reg [7:0]                       length_data_b2;

// RAM chunks used to store configuration data
// - address_table
// - length_table
// - startdata_table
// - enddata_table
dpram_hs #(.aWidth(CFG_ADDRESSWIDTH),.dWidth(24))
address_table(
    .clk(clk),
    .addr_a(ioctl_addr[CFG_ADDRESSWIDTH+2:3]),
    .we_a(address_we),
    .d_a(address_data_in),
    .addr_b(counter),
    .q_b(addr_base)
);
// Length table - variable width depending on CFG_LENGTHWIDTH
dpram_hs #(.aWidth(CFG_ADDRESSWIDTH),.dWidth(CFG_LENGTHWIDTH*8))
length_table(
    .clk(clk),
    .addr_a(ioctl_addr[CFG_ADDRESSWIDTH+2:3]),
    .we_a(length_we),
    .d_a(length_data_in),
    .addr_b(counter),
    .q_b(length)
);
dpram_hs #(.aWidth(CFG_ADDRESSWIDTH),.dWidth(8))
startdata_table(
    .clk(clk),
    .addr_a(ioctl_addr[CFG_ADDRESSWIDTH+2:3]),
    .we_a(startdata_we), 
    .d_a(ioctl_dout),
    .addr_b(counter),
    .q_b(start_val)
);
dpram_hs #(.aWidth(CFG_ADDRESSWIDTH),.dWidth(8))
enddata_table(
    .clk(clk),
    .addr_a(ioctl_addr[CFG_ADDRESSWIDTH+2:3]),
    .we_a(enddata_we),
    .d_a(ioctl_dout),
    .addr_b(counter),
    .q_b(end_val)
);

// RAM chunk used to store hiscore data
dpram_hs #(.aWidth(8),.dWidth(8))
hiscoredata (
    .clk(clk),
    .addr_a(ioctl_addr[7:0]),
    .we_a(downloading_dump),
    .d_a(ioctl_dout),
    .addr_b(local_addr[7:0]),
    .we_b(ioctl_upload),
    .d_b(ioctl_din),
    .q_b(data_to_ram)
);


always @(posedge clk)
begin
    if (downloading_config)
    begin
        // Save configuration data into tables
        if(ioctl_wr & (ioctl_addr[2:0] == 3'd1)) address_data_b3 <= ioctl_dout;
        if(ioctl_wr & (ioctl_addr[2:0] == 3'd2)) address_data_b2 <= ioctl_dout;
        if(ioctl_wr & (ioctl_addr[2:0] == 3'd4)) length_data_b2 <= ioctl_dout;
        // Keep track of the largest entry during config download
        total_entries <= ioctl_addr[CFG_ADDRESSWIDTH+2:3];
    end

    // Track completion of configuration and dump download
    if ((last_ioctl_download != ioctl_download) && (ioctl_download == 1'b0))
    begin
        if (last_ioctl_index==HS_CONFIGINDEX)
        begin
            downloaded_config <= 1'b1;
        end
        if (last_ioctl_index==HS_DUMPINDEX)
        begin
            downloaded_dump <= 1'b1;
        end
    end

    // Track completion of dump upload
    if ((last_ioctl_upload != ioctl_upload) && (ioctl_upload == 1'b0))
    begin
        if (last_ioctl_index==HS_DUMPINDEX)
        begin
            uploaded_dump <= 1'b1;
            // Mark uploaded dump as readable in case of reset
            downloaded_dump <= 1'b1;
        end
    end

    // Track last ioctl values
    last_ioctl_download <= ioctl_download;
    last_ioctl_upload <= ioctl_upload;
    last_ioctl_index <= ioctl_index;

    // Generate last address of entry to check end value
    end_addr <= addr_base + length - 1'b1;

    if(downloaded_config)
    begin
        // Check for end of state machine reset to initialise state machine
        if (reset_last == 1'b1 && reset == 1'b0)
        begin
            wait_timer = (delay > 1'b0) ? delay : delay_default;
            next_state <= 4'b0000;
            state <= 4'b1111;
            counter <= 1'b0;
            initialised <= initialised + 1'b1;
        end
        reset_last <= reset;

        // activate access signal when necessary
        ram_access <= uploading_dump | ram_write | ram_read;

        // Upload scores to HPS
        if (uploading_dump == 1'b1)
        begin
            // generate addresses to read high score from game memory. Base addresses off ioctl_address
            if (ioctl_addr == 25'b0) begin
                local_addr <= 25'b0;
                base_io_addr <= 25'b0;
                counter <= 1'b0000;
            end
            // Move to next entry when last address is reached
            if (old_io_addr!=ioctl_addr && ram_addr==end_addr[24:0])
            begin
                counter <= counter + 1'b1;
                base_io_addr <= ioctl_addr;
            end
            // Set game ram address for reading back to HPS
            ram_addr <= addr_base + (ioctl_addr - base_io_addr);
            // Set local addresses to update cached dump in case of reset
            local_addr <= ioctl_addr;
        end

        if (ioctl_upload == 1'b0 && downloaded_dump == 1'b1 && reset == 1'b0)
        begin
            // State machine to write data to game RAM
            case (state)
                4'b0000: // Initialise state machine
                begin
                    // Setup base addresses
                    local_addr <= 25'b0;
                    base_io_addr <= 25'b0;
                    // Set address for start check
                    ram_read <= 1'b0;
                    // Set wait timer
                    next_state <= 4'b0001;
                    state <= 4'b1111;
                    wait_timer <= read_defaultwait;
                end

                4'b0001: // Set start check address, enable ram read and move to start check state
                begin
                    ram_addr <= {1'b0, addr_base};
                    ram_read <= 1'b1;
                    state <= 4'b0010;
                    wait_timer <= read_defaultcheck;
                end

                4'b0010: // Start check
                    begin
                        // Check for matching start value
                        if(ioctl_din == start_val)
                        begin
                        // - If match then stop ram_read and reset timer for end check
                            ram_read <= 1'b0;
                            next_state <= 4'b0011;
                            state <= 4'b1111;
                            wait_timer <= read_defaultwait;
                        end
                        else
                        begin
                            if (wait_timer > 1'b0)
                            begin
                                wait_timer <= wait_timer - 1'b1;
                            end
                            else
                            begin
                                // - If no match after read wait then stop ram_read and retry
                                next_state <= 4'b0001;
                                state <= 4'b1111;
                                ram_read <= 1'b0;
                                wait_timer <= read_defaultwait;
                            end
                        end
                    end

                4'b0011: // Set end check address, enable ram read and move to end check state
                begin
                    ram_addr <= end_addr;
                    ram_read <= 1'b1;
                    state <= 4'b0100;
                    wait_timer <= read_defaultcheck;
                end


                4'b0100: // End check
                    begin
                        // Check for matching end value
                        // - If match then move to next state
                        // - If no match then go back to previous state
                        if (ioctl_din == end_val)
                        begin
                            if (counter == total_entries)
                            begin
                                // If this was the last entry then move to phase II, copying scores into game ram
                                state <= 4'b1001;
                                counter <= 1'b0;
                                write_counter <= 1'b0;
                                ram_write <= 1'b0;
                                ram_read <= 1'b0;
                                ram_addr <= {1'b0, addr_base};
                            end
                            else
                            begin
                                // Increment counter and restart state machine to check next entry
                                counter <= counter + 1'b1;
                                ram_read <= 1'b0;
                                state <= 4'b0000;
                            end
                        end
                        else
                        begin
                            if (wait_timer > 1'b0)
                            begin
                                wait_timer <= wait_timer - 1'b1;
                            end
                            else
                            begin
                                // - If no match after read wait then stop ram_read and retry
                                next_state <= 4'b0011;
                                state <= 4'b1111;
                                ram_read <= 1'b0;
                                wait_timer <= read_defaultwait;
                            end
                        end
                    end

                //
                //  this section walks through our temporary ram and copies into game ram
                //  it needs to happen in chunks, because the game ram isn't necessarily consecutive
                4'b0110:
                    begin
                        local_addr <= local_addr + 1'b1;
                        if (ram_addr == end_addr[24:0])
                        begin
                            if (counter == total_entries)
                            begin
                                state <= 4'b1000;
                            end
                            else
                            begin
                                // Move to next entry
                                counter <= counter + 1'b1;
                                write_counter <= 1'b0;
                                base_io_addr <= local_addr + 1'b1;
                                state <= 4'b1001;
                            end
                        end
                        else
                        begin
                            state <= 4'b1010;
                        end
                        ram_write <= 1'b0;
                    end

                4'b1000: // Hiscore write to RAM completed
                    begin
                        ram_write <= 1'b0;
                        if(write_counter < WRITE_REPEATCOUNT)
                        begin
                            // Schedule next write
                            state <= 4'b1111;
                            next_state <= 4'b1001;
                            local_addr <= 0;
                            wait_timer <= WRITE_REPEATDELAY;
                        end
                    end

                4'b1001:  // counter is correct, next state the output of our local ram will be correct
                    begin
                        write_counter <= write_counter + 1'b1;
                        state <= 4'b1010;
                    end

                4'b1010: // local ram is correct
                    begin
                        state <= 4'b1110;
                        ram_addr <= addr_base + (local_addr - base_io_addr);
                        ram_write <= 1'b1;
                    end

                4'b1110: // hold write for cycle
                    begin
                        state <= 4'b0110;
                    end

                4'b1111: // timer wait state
                    begin
                        if (wait_timer > 1'b0)
                            wait_timer <= wait_timer - 1'b1;
                        else
                            state <= next_state;
                    end
            endcase
        end
    end
    old_io_addr<=ioctl_addr;
end

endmodule

module dpram_hs #(
    parameter dWidth=8,
    parameter aWidth=8
)(
    input  clk,

    input       [aWidth-1:0]  addr_a,
    input       [dWidth-1:0]  d_a,
    input                     we_a,
    output reg  [dWidth-1:0]  q_a,

    input       [aWidth-1:0]  addr_b,
    input       [dWidth-1:0]  d_b,
    input                     we_b,
    output reg  [dWidth-1:0]  q_b
);

reg [dWidth-1:0] ram [2**aWidth-1:0];

always @(posedge clk) begin
    if (we_a) begin
        ram[addr_a] <= d_a;
        q_a <= d_a;
    end
    else
    begin
        q_a <= ram[addr_a];
    end

    if (we_b) begin
        ram[addr_b] <= d_b;
        q_b <= d_b;
    end
    else
    begin
        q_b <= ram[addr_b];
    end
end

endmodule
