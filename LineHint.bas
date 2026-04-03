#include once "windows.bi"
#include once "vbcompat.bi"
#include once "win/richedit.bi"
#include once "Inc\AkelEdit.bi"
#include once "Inc\AkelDLL.bi"

' Constant to get the first visible line in the editor (if not present in headers)
#ifndef EM_GETFIRSTVISIBLELINE
  const EM_GETFIRSTVISIBLELINE = &h00CE
#endif

sub LogInfo(byref sMsg as String)
  dim sOut as String = "[LineHint] " & sMsg
  OutputDebugString(strptr(sOut))
end sub

' --- Global Variables ---
' Pointer to the Hook Data structure managed by AkelPad
dim shared lpEditProcData as WNDPROCDATA ptr = 0
dim shared bLineHintActive as BOOL = FALSE
dim shared g_bOldRichEdit as BOOL = FALSE

' Variables to track the previous state and prevent repaints and ghost trails
dim shared rcOldHint as RECT
dim shared nOldFirstLine as Integer = -1
dim shared nOldCaretLine as Integer = -1
dim shared nOldMargin as Integer = 0

' Variable to track native AkelPad options
dim shared dwOldAkelOptions as DWORD = 0

' --- Forward Declarations ---
declare sub GetHintRect(byval hWnd as HWND, byref rc as RECT, byref bVisible as BOOL)
declare sub DrawDynamicHint(byval hWnd as HWND)

' -----------------------------------------------------------------------------
'  Drawing Logic & Positioning
' -----------------------------------------------------------------------------

' Function exclusively dedicated to calculating WHERE the Hint should go without drawing it
sub GetHintRect(byval hWnd as HWND, byref rc as RECT, byref bVisible as BOOL)
  bVisible = FALSE
  dim cr as CHARRANGE64
  dim nLine as Integer
  dim nLineIndex as Integer
  dim nLineLen as Integer
  dim ptClient as POINT
  dim res as LRESULT
  
  SendMessage(hWnd, EM_EXGETSEL64, 0, cast(LPARAM, @cr))
  nLine = SendMessage(hWnd, EM_EXLINEFROMCHAR, 0, cr.cpMin)
  nLineIndex = SendMessage(hWnd, EM_LINEINDEX, nLine, 0)
  nLineLen = SendMessage(hWnd, EM_LINELENGTH, nLineIndex, 0)
  
  if g_bOldRichEdit then
    res = SendMessage(hWnd, EM_POSFROMCHAR, nLineIndex + nLineLen, 0)
    ptClient.x = cast(short, LoWord(res))
    ptClient.y = cast(short, HiWord(res))
  else
    SendMessage(hWnd, EM_POSFROMCHAR, cast(WPARAM, @ptClient), nLineIndex + nLineLen)
  end if
  
  if ptClient.y > -10000 then
    bVisible = TRUE
    
    dim hDC as HDC = GetDC(hWnd)
    dim hFont as HFONT = cast(HFONT, SendMessage(hWnd, WM_GETFONT, 0, 0))
    dim hOldFont as HFONT
    if hFont then hOldFont = cast(HFONT, SelectObject(hDC, hFont))
    
    dim sHint as String = "<- CURRENT LINE"
    dim sz as SIZE
    GetTextExtentPoint32(hDC, strptr(sHint), Len(sHint), @sz)
    
    ' NEW: Calculate dynamic margin based on the real width of the text with Zoom
    ' sz.cx is the width in pixels. We add 40px for visual separation (20px) + safety margin.
    dim nRequiredMargin as Integer = sz.cx + 40
    if nRequiredMargin <> nOldMargin then
      SendMessage(hWnd, EM_SETMARGINS, EC_RIGHTMARGIN, nRequiredMargin shl 16)
      nOldMargin = nRequiredMargin
    end if
    
    if hFont then SelectObject(hDC, hOldFont)
    ReleaseDC(hWnd, hDC)
    
    dim rcClient as RECT
    GetClientRect(hWnd, @rcClient)
    
    ' Get the real line height for perfect background drawing
    dim nCharHeight as Integer = 0
    if not g_bOldRichEdit then
      nCharHeight = SendMessage(hWnd, AEM_GETCHARSIZE, 0, 0)
    end if
    if nCharHeight <= 0 then nCharHeight = sz.cy
    
    ' Set rc to cover the ENTIRE margin area for this line
    rc.left = rcClient.right - nOldMargin
    rc.top = ptClient.y
    rc.right = rcClient.right
    rc.bottom = ptClient.y + nCharHeight
  end if
end sub


sub DrawDynamicHint(byval hWnd as HWND)
  dim rc as RECT
  dim bVisible as BOOL
  
  ' Reuse the logic function to get the drawing coordinates
  GetHintRect(hWnd, rc, bVisible)
  
  if bVisible then
    dim hDC as HDC = GetDC(hWnd)
    if hDC = 0 then exit sub
    
    ' --- FILL THE MARGIN BACKGROUND WITH THE THEME COLOR ---
    dim hBrush as HBRUSH = 0
    dim bFill as BOOL = FALSE
    
    if not g_bOldRichEdit then
      dim dwOptions as DWORD = SendMessage(hWnd, AEM_GETOPTIONS, 0, 0)
      if (dwOptions and AECO_ACTIVELINE) then
        dim aec as AECOLORS
        ' CORRECTION: We explicitly tell AkelPad which color we want to get
        aec.dwFlags = AECLR_ACTIVELINEBK
        SendMessage(hWnd, AEM_GETCOLORS, 0, cast(LPARAM, @aec))
        
        hBrush = CreateSolidBrush(aec.crActiveLineBk)
        bFill = TRUE
      end if
    end if
    
    if bFill andalso hBrush then
      FillRect(hDC, @rc, hBrush)
      DeleteObject(hBrush)
    end if
    ' ----------------------------------------------------------
    
    SetBkMode(hDC, TRANSPARENT)
    SetTextColor(hDC, &H0000FF) 
    
    dim hFont as HFONT = cast(HFONT, SendMessage(hWnd, WM_GETFONT, 0, 0))
    dim hOldFont as HFONT
    if hFont then hOldFont = cast(HFONT, SelectObject(hDC, hFont))
    
    dim sHint as String = "<- CURRENT LINE"
    dim sz as SIZE
    GetTextExtentPoint32(hDC, strptr(sHint), Len(sHint), @sz)
    
    dim rcClient as RECT
    GetClientRect(hWnd, @rcClient)
    dim drawX as Integer = rcClient.right - sz.cx - 20
    
    ' Center the text vertically within the editor's line height
    dim drawY as Integer = rc.top + ((rc.bottom - rc.top) - sz.cy) \ 2
    
    TextOut(hDC, drawX, drawY, strptr(sHint), Len(sHint))
    
    if hFont then SelectObject(hDC, hOldFont)
    ReleaseDC(hWnd, hDC)
  end if
end sub

' -----------------------------------------------------------------------------
'  Global Edit Window Subclass (AKD_SETEDITPROC)
' -----------------------------------------------------------------------------
function EditGlobalProc stdcall (byval hWnd as HWND, byval uMsg as UINT, byval wParam as WPARAM, byval lParam as LPARAM) as LRESULT
  dim lRes as LRESULT
  dim rcUpdate as RECT
  dim bNeedRedraw as BOOL = FALSE
  
  ' Pre-processing
  select case uMsg
    case WM_PAINT
      ' Find out which area of the screen Windows is requesting to repaint
      GetUpdateRect(hWnd, @rcUpdate, FALSE)
      dim rcIntersect as RECT
      
      ' Magic: If Windows is going to overwrite our text, we flag that we must redraw it.
      if (rcOldHint.right = 0) orelse IntersectRect(@rcIntersect, @rcUpdate, @rcOldHint) then
        bNeedRedraw = TRUE
      end if
      
    case WM_SETFOCUS
      ' Protect the right margin with the currently calculated dynamic value
      if nOldMargin > 0 then
        SendMessage(hWnd, EM_SETMARGINS, EC_RIGHTMARGIN, nOldMargin shl 16)
      end if
      
      ' Re-apply active line highlight if switching tabs
      if not g_bOldRichEdit then
        SendMessage(hWnd, AEM_SETOPTIONS, AECOOP_OR, AECO_ACTIVELINE)
      end if
      
    case WM_SIZE, WM_MOUSEWHEEL, WM_VSCROLL, WM_HSCROLL
      ' ONLY on Scroll/Resize events do we clear the trail BEFORE 
      ' the OS moves the pixels on the screen, avoiding a duplicated visual trail.
      if rcOldHint.right > 0 then InvalidateRect(hWnd, @rcOldHint, TRUE)
  end select
  
  ' Execute AkelPad's native action
  if lpEditProcData andalso lpEditProcData->NextProc then
    lRes = lpEditProcData->NextProc(hWnd, uMsg, wParam, lParam)
  else
    lRes = 0
  end if

  ' Post-processing
  if uMsg = WM_PAINT then
    ' We draw solely and exclusively if Windows erased our area in this cycle
    if bNeedRedraw then
      DrawDynamicHint(hWnd)
    end if
  else
    ' Interactive events that COULD change the cursor position
    select case uMsg
      case WM_KEYDOWN, WM_KEYUP, WM_SYSKEYDOWN, WM_SYSKEYUP, _
           WM_LBUTTONDOWN, WM_LBUTTONUP, WM_MOUSEMOVE, _
           WM_MOUSEWHEEL, WM_HSCROLL, WM_VSCROLL, WM_CHAR, WM_SIZE
           
        ' Filter mouse movements without a sustained click
        if (uMsg <> WM_MOUSEMOVE) orelse (wParam and MK_LBUTTON) then
          dim rcNew as RECT
          dim bVisible as BOOL
          
          ' OPTIMIZATION: Where SHOULD the Hint be right now?
          GetHintRect(hWnd, rcNew, bVisible)
          
          if bVisible then
            ' Find out the current line and logical scroll offset to safeguard tracking
            dim nFirstVisible as Integer = SendMessage(hWnd, EM_GETFIRSTVISIBLELINE, 0, 0)
            dim crPos as CHARRANGE64
            SendMessage(hWnd, EM_EXGETSEL64, 0, cast(LPARAM, @crPos))
            dim nCaretLine as Integer = SendMessage(hWnd, EM_EXLINEFROMCHAR, 0, crPos.cpMin)

            ' DRAW ONLY ONCE: Check if the physical rectangle or logical line changed
            if (rcNew.top <> rcOldHint.top) or (rcNew.left <> rcOldHint.left) or _
               (rcNew.right <> rcOldHint.right) or (rcNew.bottom <> rcOldHint.bottom) or _
               (nFirstVisible <> nOldFirstLine) or (nCaretLine <> nOldCaretLine) then
               
               ' Position, line, or scroll changed!
               ' 1. Rigorously erase the previous area
               if rcOldHint.right > 0 then InvalidateRect(hWnd, @rcOldHint, TRUE)
               ' 2. Indicate drawing the new area (erasing the background so it stays clean)
               InvalidateRect(hWnd, @rcNew, TRUE)
               
               ' 3. Save the new position HERE, ensuring correct synchronization
               rcOldHint = rcNew
               nOldFirstLine = nFirstVisible
               nOldCaretLine = nCaretLine
            end if
          else
            ' If it is no longer visible (e.g., scrolled off the top of the screen)
            if rcOldHint.right > 0 then
              InvalidateRect(hWnd, @rcOldHint, TRUE)
              rcOldHint.left = 0 : rcOldHint.right = 0 : rcOldHint.top = 0 : rcOldHint.bottom = 0
              nOldFirstLine = -1
              nOldCaretLine = -1
            end if
          end if
        end if
    end select
  end if

  return lRes
end function

' -----------------------------------------------------------------------------
'  Exported Functions
' -----------------------------------------------------------------------------

extern "C"

sub DllAkelPadID alias "DllAkelPadID" (byval pv as PLUGINVERSION ptr) export
  pv->dwAkelDllVersion = AKELDLL
  pv->dwExeMinVersion3x = MAKE_IDENTIFIER(-1, -1, -1, -1)
  pv->dwExeMinVersion4x = MAKE_IDENTIFIER(4, 9, 7, 0)
  pv->pPluginName = @"LineHint"
end sub

sub ToggleLineHint alias "ToggleLineHint" (byval pd as PLUGINDATA ptr) export
  pd->dwSupport or= PDS_NOAUTOLOAD
  if (pd->dwSupport and PDS_GETSUPPORT) then exit sub

  LogInfo("--- ToggleLineHint Called ---")
  g_bOldRichEdit = pd->bOldRichEdit

  if bLineHintActive then
    ' --- DEACTIVATE ---
    LogInfo("Deactivating Global Edit Hook...")
    pd->nUnload = UD_UNLOAD
    
    SendMessage(pd->hMainWnd, AKD_SETEDITPROC, 0, cast(LPARAM, @lpEditProcData))
    bLineHintActive = FALSE
    
    if pd->hWndEdit then 
      ' Restore normal margin
      SendMessage(pd->hWndEdit, EM_SETMARGINS, EC_RIGHTMARGIN, 0)
      
      ' Restore original options
      if not g_bOldRichEdit then
        SendMessage(pd->hWndEdit, AEM_SETOPTIONS, AECOOP_SET, dwOldAkelOptions)
      end if
      
      InvalidateRect(pd->hWndEdit, 0, TRUE)
    end if
    
  else
    ' --- ACTIVATE ---
    LogInfo("Activating Global Edit Hook...")
    pd->nUnload = UD_NONUNLOAD_ACTIVE
    
    ' Initialize line and margin tracking memory from scratch upon activation
    rcOldHint.left = 0 : rcOldHint.right = 0 : rcOldHint.top = 0 : rcOldHint.bottom = 0
    nOldFirstLine = -1
    nOldCaretLine = -1
    nOldMargin = 0
    
    ' Register the hook. AkelPad will fill lpEditProcData
    SendMessage(pd->hMainWnd, AKD_SETEDITPROC, cast(WPARAM, @EditGlobalProc), cast(LPARAM, @lpEditProcData))
    bLineHintActive = TRUE
    
    if pd->hWndEdit then 
      ' Enable native AkelEdit highlighting (only if not old MS RichEdit)
      if not g_bOldRichEdit then
        ' Save previous state
        dwOldAkelOptions = SendMessage(pd->hWndEdit, AEM_GETOPTIONS, 0, 0)
        ' Activate the native active background option WITHOUT modifying the theme color
        SendMessage(pd->hWndEdit, AEM_SETOPTIONS, AECOOP_OR, AECO_ACTIVELINE)
      end if
      
      ' Force a complete repaint cycle
      InvalidateRect(pd->hWndEdit, 0, TRUE)
    end if
  end if
  
  LogInfo("--- ToggleLineHint Finished ---")
end sub

end extern

function DllMain(byval hinstDLL as HINSTANCE, byval fdwReason as DWORD, byval lpvReserved as LPVOID) as WINBOOL
  return TRUE
end function