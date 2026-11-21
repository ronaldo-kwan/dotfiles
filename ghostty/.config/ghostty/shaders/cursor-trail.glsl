// Cursor trail for Ghostty: when the cursor moves, a soft streak in the cursor's colour
// glides from where it was to where it is and fades out, in about 0.18 seconds.
// Written for these dotfiles. It uses Ghostty's cursor uniforms (iCurrentCursor,
// iPreviousCursor, iTimeCursorChange: see `ghostty +show-config --default --docs`).
// To switch it off, remove the `custom-shader` line from ~/.config/ghostty/config.

const float DURATION = 0.18;   // seconds from the move until the trail is gone
const float STRENGTH = 0.55;   // how solid the trail is, next to the cursor (0 to 1)

// Distance from p to a box of half-size b, centred on (0, 0)
float boxDistance(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec4 screen = texture(iChannel0, fragCoord / iResolution.xy);
    fragColor = screen;

    float t = (iTime - iTimeCursorChange) / DURATION;
    if (t >= 1.0 || iFocus == 0) return;                  // no recent move, or not focused
    if (iPreviousCursor.z <= 0.0 || iCurrentCursor.z <= 0.0) return;   // no cursor yet

    // Centres of the cursor before and now (xy is its left, top corner; y goes up)
    vec2 now = iCurrentCursor.xy + vec2(0.5, -0.5) * iCurrentCursor.zw;
    vec2 before = iPreviousCursor.xy + vec2(0.5, -0.5) * iPreviousCursor.zw;
    vec2 path = now - before;
    if (dot(path, path) < 1.0) return;                     // it didn't move (a colour change)

    // The tail starts where the cursor was and catches up with it, slowing down at the end
    float caught = 1.0 - pow(1.0 - clamp(t, 0.0, 1.0), 3.0);
    vec2 tail = before + path * caught;

    // The cursor's shape, swept from the tail to the cursor
    vec2 toTail = fragCoord - tail;
    vec2 span = now - tail;
    float along = clamp(dot(toTail, span) / max(dot(span, span), 1.0), 0.0, 1.0);
    vec2 halfSize = max(0.5 * iCurrentCursor.zw, vec2(1.0));
    float d = boxDistance(fragCoord - (tail + span * along), halfSize);
    float inside = clamp(0.5 - d, 0.0, 1.0);               // soft, anti-aliased edge

    // Faint at the tail, stronger next to the cursor, and fading as it catches up
    float alpha = inside * STRENGTH * mix(0.25, 1.0, along) * (1.0 - t);
    fragColor = vec4(mix(screen.rgb, iCurrentCursorColor.rgb, alpha), screen.a);
}
