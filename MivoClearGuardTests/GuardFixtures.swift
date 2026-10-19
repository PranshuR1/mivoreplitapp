import Foundation

/// DOM fixtures shaped like the routes the guard actually has to judge.
///
/// The guard's heuristics are all size-relative — a "large" video is one at least
/// 40% of `innerHeight` tall or 62% of `innerWidth` wide, a reply box has to be
/// over 40x18 and on screen — so every element here carries explicit dimensions.
/// Sizes stated in `vw`/`vh` keep the fixtures honest against
/// `GuardHarness.viewportSize` without hard-coding pixel counts.
enum GuardFixtures {
    private static func page(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
          <head><meta name="viewport" content="width=device-width, initial-scale=1"></head>
          <body style="margin:0;padding:0">
        \(body)
          </body>
        </html>
        """
    }

    /// A reel shared into a DM, still playing, nothing scrolled past it.
    ///
    /// The "Reply to yourself..." box plus the large video is what the guard reads
    /// as an inline single-media viewer.
    static let instagramSharedReelPlaying = page("""
        <header style="height:44px"><h2 style="margin:0">You</h2></header>
        <video src="https://scontent.example/shared-reel.mp4"
               style="display:block;width:100vw;height:80vh"></video>
        <input placeholder="Reply to yourself..."
               style="display:block;width:90vw;height:44px">
        """)

    /// The reported bug, shaped like the DOM in the screen recording rather than
    /// like convenient markup.
    ///
    /// Two details are load-bearing and both were wrong in the first draft of this
    /// fixture:
    ///   * "Suggested" is a plain `div`, not a heading or a span. The old
    ///     `querySelectorAll("h1, h2, h3, h4, [role='heading'], span")` never saw it.
    ///   * The "Reply to" box is gone, replaced by a "Send to chat" pill. That is
    ///     what used to tear down the inline-viewer flag and disarm every other
    ///     check at exactly the wrong moment.
    static let instagramSuggestedReel = page("""
        <div style="height:24px"><div style="margin:0">Suggested</div></div>
        <div style="margin:0;height:28px">The 100 Quack Challenge</div>
        <video src="https://scontent.example/suggested-reel.mp4"
               style="display:block;width:100vw;height:70vh"></video>
        <div role="button" style="display:block;width:60vw;height:36px">Send to chat</div>
        """)

    /// The 2026-08-04 recording: a suggested reel with **no "Suggested" text
    /// reachable at all** — the label is clipped out of the compact header — and
    /// the conversation's "Reply to …" box replaced by a "Send to group" pill.
    ///
    /// This is the fixture that fails on label matching alone, which is why the
    /// reply-to → send-to swap is a second, independent signal.
    static let instagramSuggestedReelNoLabel = page("""
        <header style="height:24px"><span style="margin:0">&lt;</span></header>
        <video src="https://scontent.example/next-reel.mp4"
               style="display:block;width:100vw;height:70vh"></video>
        <div style="height:20px">adudewithadogg</div>
        <div role="button" style="display:block;width:60vw;height:36px">Send to group</div>
        """)

    /// The shared reel in the same compact layout: the reply box is present, so
    /// the send-to signal must stay quiet.
    static let instagramSharedReelCompact = page("""
        <header style="height:24px"><span style="margin:0">You</span></header>
        <video src="https://scontent.example/shared-reel.mp4"
               style="display:block;width:100vw;height:70vh"></video>
        <input placeholder="Reply to hersh_m19..."
               style="display:block;width:90vw;height:40px">
        """)

    /// The same escape with the label in a `span`, the tag the original selector
    /// did handle. Matching text nodes has to stay a superset of that selector,
    /// not a replacement for it.
    static let instagramSuggestedReelSpanLabel = page("""
        <div style="height:24px"><span style="margin:0">Suggested</span></div>
        <video src="https://scontent.example/suggested-reel.mp4"
               style="display:block;width:100vw;height:70vh"></video>
        """)

    /// The false positive this has to keep dodging: the DM inbox has its own
    /// "Suggested" people section, and no video anywhere. Returning the viewer
    /// home from here would fire every time they opened their messages.
    ///
    /// The label is a `div` here too — with the text-node matching that fixes the
    /// case above, this is the fixture that proves the fix did not overreach.
    static let instagramInboxSuggestedPeople = page("""
        <header style="height:44px"><div style="margin:0">Messages</div></header>
        <div style="margin:0;height:32px">Suggested</div>
        <ul style="margin:0">
          <li style="height:56px">alex</li>
          <li style="height:56px">sam</li>
          <li style="height:56px">jordan</li>
        </ul>
        """)

    /// A single TikTok video opened from a message, with the player on screen.
    static let tiktokSingleVideo = page("""
        <header style="height:44px"><h2 style="margin:0">Shared a video</h2></header>
        <video src="https://v.example/shared-video.mp4"
               style="display:block;width:100vw;height:80vh"></video>
        """)

    /// A blocked route — nothing on the page matters, the guard judges the URL.
    static let genericFeed = page("""
        <main style="height:200vh"><h1>Feed</h1></main>
        """)
}
