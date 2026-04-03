const std = @import("std");
const chip8_core = @import("chip8_core");

pub const SCREEN_H: usize = 32;
pub const SCREEN_W: usize = 64;

pub const RAM_SIZE: usize = 4096;
pub const NUM_REGS: usize = 16;
pub const STACK_SIZE: usize = 16;
pub const START_ADDR: u16 = 0x200;

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

    fn execute(self: *Emu, op: u16) void {}

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
