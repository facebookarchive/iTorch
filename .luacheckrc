-- -*- mode: lua; -*-
std = "luajit"

globals = {
    "torch",
    "include",
    "image",
    "ifx",
    "itorch",
    "jit",
}

files["init.lua"].redefined = false
files["test.lua"].redefined = false
unused_args = false
allow_defined = true
