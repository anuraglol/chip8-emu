const std = @import("std");
const chip8_core = @import("chip8_core");

pub const SCREEN_H: usize = 32;
pub const SCREEN_W: usize = 64;

pub const RAM_SIZE: usize = 4096;
pub const NUM_REGS: usize = 16;
pub const STACK_SIZE: usize = 16;
pub const START_ADDR: u16 = 0x200;
pub const NUM_KEYS: usize = 16;

const UN_ERR = error.UnimplementedOpCode;

const FONTSET_SIZE: usize = 80;
const FONTSET: [FONTSET_SIZE]u8 = [FONTSET_SIZE]u8{
    0xF0, 0x90, 0x90, 0x90, 0xF0, // 0
    0x20, 0x60, 0x20, 0x20, 0x70, // 1
    0xF0, 0x10, 0xF0, 0x80, 0xF0, // 2
    0xF0, 0x10, 0xF0, 0x10, 0xF0, // 3
    0x90, 0x90, 0xF0, 0x10, 0x10, // 4
    0xF0, 0x80, 0xF0, 0x10, 0xF0, // 5
    0xF0, 0x80, 0xF0, 0x90, 0xF0, // 6
    0xF0, 0x10, 0x20, 0x40, 0x40, // 7
    0xF0, 0x90, 0xF0, 0x90, 0xF0, // 8
    0xF0, 0x90, 0xF0, 0x10, 0xF0, // 9
    0xF0, 0x90, 0xF0, 0x90, 0x90, // A
    0xE0, 0x90, 0xE0, 0x90, 0xE0, // B
    0xF0, 0x80, 0x80, 0x80, 0xF0, // C
    0xE0, 0x90, 0x90, 0x90, 0xE0, // D
    0xF0, 0x80, 0xF0, 0x80, 0xF0, // E
    0xF0, 0x80, 0xF0, 0x80, 0x80, // F
};

const DEFAULT_EMU = Emu{
    .pc = START_ADDR,
    .ram = [_]u8{0} ** RAM_SIZE,
    .screen = [_]bool{false} ** (SCREEN_H * SCREEN_W),
    .v_reg = [_]u8{0} ** NUM_REGS,
    .i_reg = 0,
    .keys = [_]bool{false} ** NUM_KEYS,
    .sp = 0,
    .stack = [_]u16{0} ** STACK_SIZE,
    .dt = 0,
    .st = 0,
};

pub const Emu = struct {
    pc: u16, // program counter
    ram: [RAM_SIZE]u8, // 4K memory
    screen: [SCREEN_H * SCREEN_W]bool, // monochrome display (64x32)
    v_reg: [NUM_REGS]u8, // 16 8-bit general purpose registers (V0 to VF)
    i_reg: u16, // 16-bit index register
    sp: u16, // stack pointer
    stack: [STACK_SIZE]u16, // stack for subroutine calls (up to 16 levels)
    dt: u8, // delay timer
    st: u8, // sound timer
    keys: [NUM_KEYS]bool,

    pub fn init() Emu {
        const new_emu = DEFAULT_EMU;
        new_emu.ram = FONTSET;

        return new_emu;
    }

    pub fn reset(self: *Emu) void {
        self.* = DEFAULT_EMU;

        for (FONTSET, 0..) |byte, idx| {
            self.ram[idx] = byte;
        }
    }

    pub fn push(self: *Emu, val: u16) void {
        self.stack[self.sp] = val;
        self.sp = self.sp + 1;
    }

    pub fn pop(self: *Emu) u16 {
        self.sp = self.sp - 1;
        return self.stack[self.sp];
    }

    fn fetch(self: *Emu) !u16 {
        const higher_byte = self.ram[self.sp];
        const lower_byte = self.ram[self.sp + 1];
        const op: u16 = (@as(u16, higher_byte) << 8) | @as(u16, lower_byte);
        self.pc = self.pc + 2;
        return op;
    }

    fn execute(self: *Emu, op: u16) void {
        const d1 = (op & 0xF000) >> 12;
        const d2 = (op & 0x0F00) >> 8;
        const d3 = (op & 0x00F0) >> 4;
        const d4 = op & 0x000F;

        switch (op & 0xF000) {
            0x0000 => switch (op) {
                0x00E0 => self.screen = [_]bool{false} ** (SCREEN_H * SCREEN_W),
                0x00EE => {
                    const ret_addr = self.pop();
                    self.pc = ret_addr;
                },
                else => {},
            },

            0x1000 => {
                const nnn = op & 0x0FFF; // extracts the NNN part, from 0x1NNN, we match op & 0xF000 basically the first digit
                self.pc = nnn;
            },

            0x2000 => {
                const nnn = op & 0x0FFF;
                self.push(self.pc);
                self.pc = nnn;
            },

            0x3000 => { // skip next if VX == NN, format is 3XNN, x is second digit basically, NN is what follows after
                const x = d2;
                const nn = (op & 0xFF);
                if (self.v_reg[x] == nn) {
                    self.pc = self.pc + 2;
                }
            },

            0x4000 => { // skip next if VX != NN, format is 4XNN, x is second digit basically, NN is what follows after
                const x = d2;
                const nn = (op & 0xFF);
                if (self.v_reg[x] != nn) {
                    self.pc = self.pc + 2;
                }
            },

            0x5000 => { // 5XY0, skip next if VX == VY
                const x = d2;
                const y = d3;
                if (self.v_reg[x] == self.v_reg[y]) {
                    self.pc = self.pc + 2;
                }
            },

            0x6000 => { // 6XNN, VX = NN, set the V register specified by the second register to the value given
                const x = d2;
                const nn: u8 = @intCast(op & 0x00FF);
                self.v_reg[x] = nn;
            },

            0x7000 => {
                const x = d2;
                const nn: u8 = @intCast(op & 0x00FF);
                self.v_reg[x] = self.v_reg[x] +% nn; // wrapping add - refer to zig docs
            },

            0x8000 => {
                switch (d4) { // all match 0x8XYZ, where Z is the 4th digit thats changing
                    0 => {
                        const x = d2;
                        const y = d3;
                        self.v_reg[x] = self.v_reg[y];
                    },
                    1 => {
                        const x = d2;
                        const y = d3;
                        self.v_reg[x] = self.v_reg[x] | self.v_reg[y];
                    },
                    2 => {
                        const x = d2;
                        const y = d3;
                        self.v_reg[x] = self.v_reg[x] & self.v_reg[y];
                    },
                    3 => {
                        const x = d2;
                        const y = d3;
                        self.v_reg[x] = self.v_reg[x] ^ self.v_reg[y];
                    },
                    4 => {
                        const x = d2;
                        const y = d3;
                        const new_vx, const overflow = @addWithOverflow(self.v_reg[x], self.v_reg[y]);
                        const new_vf = if (overflow) 1 else 0;

                        self.v_reg[x] = new_vx;
                        self.v_reg[0xF] = new_vf; // in the 16th register, we store if an overflow happened, aka the carry flag
                    },
                    5 => {
                        const x = d2;
                        const y = d3;
                        const new_vx, const overflow = @addWithOverflow(self.v_reg[x], self.v_reg[y]);
                        const new_vf = if (overflow) 0 else 1; // borrow instead of carry flag this time

                        self.v_reg[x] = new_vx;
                        self.v_reg[0xF] = new_vf;
                    },
                    6 => {
                        const x = d2;
                        const lsb = self.v_reg[x] & 1;
                        self.v_reg[x] >>= 1;
                        self.v_reg[0xF] = lsb;
                    },
                    7 => {
                        const x = d2;
                        const y = d3;
                        const new_vx, const overflow = @addWithOverflow(self.v_reg[x], self.v_reg[y]);
                        const new_vf = if (overflow) 0 else 1;

                        self.v_reg[x] = new_vx;
                        self.v_reg[0xF] = new_vf;
                    },
                    0xE => {
                        const x = d2;
                        const msb = (self.v_reg[x] & 0x80) >> 7;
                        self.v_reg[x] <<= 1;
                        self.v_reg[0xF] = msb;
                    },
                    else => UN_ERR,
                }
            },

            0x9000 => {
                const x, const y = [_]u16{ d2, d3 };
                if (self.v_reg[x] != self.v_reg[y]) {
                    self.pc = self.pc + 2;
                }
            },

            0xA000 => {
                const nnn = op & 0x0FFF;
                self.i_reg = nnn;
            },

            0xB000 => {
                const nnn = op & 0x0FFF;
                self.pc = self.v_reg[0] + nnn;
            },

            0xC000 => { // imp, this is the chip8's random number generation
                var prng = std.rand.DefaultPrng.init(12345); // seed
                var random = prng.random();

                const rng: u8 = random.int(u8);
                const x = d2;
                const nn = (op & 0xFF);
                self.v_reg[x] = rng & nn;
            },

            0xD000 => {
                // draw sprite function, we'll do it later
            },

            0xE000 => {
                switch (d3) {
                    9 => {
                        const x = d2;
                        const vx = self.v_reg[x];
                        const key = self.keys[vx];
                        if (key) {
                            self.pc = self.pc + 2;
                        }
                    },
                    0xA => {
                        const x = d2;
                        const vx = self.v_reg[x];
                        const key = self.keys[vx];
                        if (!key) {
                            self.pc = self.pc + 2;
                        }
                    },
                    else => UN_ERR,
                }
            },

            0xF000 => {
                const AB = op & 0x00FF;
                const x = d2;
                switch (AB) {
                    0x07 => self.v_reg[x] = self.dt,
                    0x0A => {
                        // waits for key press, stores index in VX, imp
                        const pressed = false;
                        for (self.keys, 0..) |key, i| {
                            if (key) {
                                self.v_reg[x] = i;
                                pressed = true;
                                break;
                            }
                        }

                        if (!pressed) self.pc = self.pc - 2; // redo opcode
                    },
                    0x15 => self.dt = self.v_reg[x],
                    0x18 => self.st = self.v_reg[x],
                    0x1E => self.i_reg = self.i_reg +% self.v_reg[x],

                    0x29 => {
                        const c = self.v_reg[x];
                        self.i_reg = c * 5; // since all font sprites take up 5 bytes each, the ram address is basically c times 5
                    },

                    0x33 => {
                        // store bcd encoding of vx into i todo
                    },

                    0x55 => {
                        const i = self.i_reg;
                        for (0..x) |idx| {
                            self.ram[i + idx] = self.v_reg[idx];
                        }
                    },

                    0x65 => {
                        const i = self.i_reg;
                        for (0..x) |idx| {
                            self.v_reg[idx] = self.ram[i + idx];
                        }
                    },
                }
            },

            else => UN_ERR,
        }
    }

    pub fn tick(self: *Emu) !void {
        const op = self.fetch();
        self.execute(self, op);
    }

    pub fn tick_timers(self: *Emu) void {
        if (self.dt > 0) {
            self.dt = self.dt - 1;
        }
        if (self.st > 0) {
            if (self.st == 1) {
                // beep
            }
            self.st = self.st - 1;
        }
    }
};

pub fn main() !void {
    std.debug.print("All your {s} are belong to us.\n", .{"codebase"});
    try chip8_core.bufferedPrint();
}
