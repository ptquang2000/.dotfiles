# Math notation rules

The interfaces used with this harness cannot reliably render LaTeX formulas:
the terminal TUI shows raw LaTeX source, and the KaTeX-based clients only
understand `$...$` / `$$...$$` delimiters. Follow these rules whenever you
write math:

1. **Default to Unicode plain-text math.** Use symbols like `α β γ π Σ ∫ √ ≤ ≥
   ≠ ≈ → ∞` together with ASCII operators (` + - * / = ^ _ `) instead of LaTeX
   commands. Example: `x = (α² + b²) / 2` instead of `x = \frac{\alpha^2 + b^2}{2}`.
   Keep expressions short enough to stay readable in a terminal.

2. **Use LaTeX only when the user asks for it.** When they do, or when writing
   files intended for real LaTeX/typesetting, write it as:
   - inline: `$x^2 + y^2$`
   - display: `$$x_{n+1} = x_n^2$$` (on its own line, blank line around it)
   - **Never** use `\(...\)`, `\[...\]`, or `\begin{aligned}`/`\end{aligned}`
     outside actual `.tex` documents. Those delimiters are not rendered and
     always leak as raw source.

3. **Prefer words or code in dense output.** In long explanations, tables, or
   code comments, spell parts of the math out or give a small Python/NumPy
   snippet instead of a wide inline formula.
