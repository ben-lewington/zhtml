- [ ] HTML escape what needs to be HTML escaped
- [ ] token parsing
- [ ] parsing attributes correctly
- [ ] interpolate values into Template struct - initialiser vs. render function with args
- [ ] attribute interpolation -> how to allow modifiers?
- [ ] test suite for interp
- [ ] comptime error handling -> atm we do catch unreachable, will need to switch on the returned
    error. These will be zig errors (i.e. stateless), so I'm thinking it's the responsibility of
    the error site to reset the tokeniser position, so that you can report the error against the
    specific token that the error occurred on.

