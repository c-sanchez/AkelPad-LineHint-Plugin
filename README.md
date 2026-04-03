Initially, this was inspired by the "EOL annotations" feature found in Scintilla-based editors (like Notepad++). I wanted a way to display a virtual overlay next to the active line without actually modifying the document's text.

Currently, it draws a highly visible <- CURRENT LINE indicator on the far right side of whichever line your text caret is on. However, underneath the hood, it also serves as a robust, heavily-commented template for anyone wanting to write AkelPad plugins in FreeBASIC, specifically plugins that need to safely perform custom GDI drawing over the editor.

Features:

Virtual Text Overlay: Draws a floating text hint on the active line that follows your cursor in real-time.

Smart Margin Protection: It dynamically adjusts the AkelEdit EC_RIGHTMARGIN. This means if you type a very long line, the text will naturally wrap before it hits the line hint—your document text will never overlap with the drawn graphic!

Native Theme Integration: It queries AkelPad's native color engine (AEM_GETCOLORS). The background of the line hint perfectly matches whatever Active Line background color is defined by your current AkelPad theme (Dark, Light, Notepad++, etc.).

Flicker-Free Rendering: Custom GDI drawing can often cause terrible screen flickering. This plugin uses highly optimized intersection and InvalidateRect tracking. It only repaints the exact pixels that changed, preventing ghost trails when scrolling or typing.

MDI Support: Fully supports multi-tab environments. The hint and active line highlights update correctly when switching between document tabs.

For Developers: A FreeBASIC Plugin Template:

Why FreeBASIC?
FreeBASIC is an incredibly powerful language that produces very small, highly optimized compiled binaries. It is extremely easy to use and generally produces much shorter, cleaner code than writing the exact same logic in C or C++. Because it has direct access to the Win32 API but a much friendlier syntax, it is an excellent entry point for developing AkelPad plugins without getting bogged down by the complexities and heavy boilerplate of C.

If you are interested in plugin development, this codebase solves several common hurdles when interacting with the AkelEdit control.
The source code demonstrates how to:

1. Subclass the Editor: Safely install and chain a global Window Procedure hook (AKD_SETEDITPROC) to intercept WM_PAINT, keyboard, and mouse events.

2. Coordinate Translation: Use EM_POSFROMCHAR to convert character indices into exact X/Y screen coordinates.

3. Safe GDI Overlay Drawing: How to draw text and fill rectangles over the editor text after AkelPad finishes painting, without causing resource leaks.

4. Interact with AkelEdit Native API: Enable native options (AECO_ACTIVELINE) and retrieve theme colors (AECLR_ACTIVELINEBK) on the fly.

AI Assistance & Feedback:

This plugin was developed with the help of Artificial Intelligence (Gemini) to navigate the Win32 API and AkelPad's internal messaging system.

All comments, ideas, improvements, and custom modifications are highly welcome! Whether you want to fork it to add actual compiler errors to the EOL annotations, or just use it as a base to learn plugin creation, feel free to dive in.