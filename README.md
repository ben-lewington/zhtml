# zhtml

**zhtml** is a Zig-based HTML-like templating engine designed for fast, type-safe, and composable markup generation. It features a custom syntax for HTML, supports value interpolation, and is built for compile-time safety and performance.

## Features

- **Custom HTML-like Syntax:** Write markup in a concise, readable format.
- **Type-Safe Interpolation:** Compile-time checked value interpolation into templates.
- **Whitespace and Attribute Handling:** Handles whitespace and attributes robustly.
- **HTML Escaping:** Built-in escaping for safe output.
- **Snapshot Testing:** Includes a suite of snapshot tests for template rendering.

## Example

Given a template file `example.zhtml`:

    !doctype html!
    # a comment #
    <html lang="en" data-fallback .font-sans .antialiased .w-screen |
        <head |
            <script | document.documentElement.removeAttribute('data-fallback')>
            <meta charset="utf-8">
            <meta name="viewport" content="width=device-width,initial-scale=1">
            <link href="/global.css" rel="stylesheet">
            <title|My Title>
        >
        <body |
            <header .flex.justify-center | <.max-w-md.lg:max-w-6xl | Header Content >>
            <main #main .flex.justify-center |
                <.max-w-md.lg:max-w-6xl|
                    Main Content
                    @{.content}
                    @if (x) {
                        <a|@{x}>
                    } else { <> }
                    @if |y| { <a|@{y}> }
                    @for (z) { <tag|@x> }
                    @for (t) { <tag @x| @{i}-th node> }
                    @switch (w) {
                        .a => { <tag @{x} |@{i}-th node> }
                        .b => { <tag @{x} |@{i}-th node> }
                        .c => { <tag @{x} |@{i}-th node> }
                    }
                >
            >
            <footer .flex.justify-center | <.max-w-md.lg:max-w-6xl | Footer Content >>
        >
    >

You can parse and render it in Zig:

    const parser = @import("parser.zig");
    const Template = @import("new.zig").Template;

    const ir = comptime parser.parseTopNodeComptime(
        \\<a|The content is @content>
    ) catch unreachable;
    const templ = Template(.interp, ir);

    const stdout = std.io.getStdOut().writer();
    const foo: []const u8 = "foo";
    try templ.render(stdout, .{ .content = foo });

## Usage

### Build

    zig build

### Run

    zig build run

### Test

    zig build test

## Project Structure

- `src/new.zig` — Main template engine logic and entry point.
- `src/parser.zig` — Parser for the custom HTML-like syntax.
- `src/tokeniser.zig` — Tokenizer for breaking input into tokens.
- `src/escape.zig` — HTML escaping utilities.
- `example.zhtml` — Example template file.
- `build.zig` — Zig build script.

## Syntax Overview

- `!doctype html!` — Meta declarations.
- `# comment #` — Comments.
- `<tag| ... >` — Tag with content.
- `.class`, `#id` — Shorthand for classes and IDs.
- `@name` — Interpolated value.
- Control flow: `@if`, `@for`, `@switch` (see `example.zhtml`).

## Testing

Snapshot tests are defined in `src/new.zig` and run via `zig build test`. These ensure that template rendering matches expected output.

## License

MIT

---

**Note:** This project is experimental and under active development. 