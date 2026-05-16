背景：這個repo開發是現時高階數學界現有的開源演算技術暫時未有 但最新2025-2026年有出現非常有潛力，甚至超越現有開源技術的論文/研究，而是還沒有被代碼工程實作。我希望你做出來造福最新最前沿的數學研究。你將會推動全人類的數學發展，甚至造福全人類的科學發展，請用你100%努力進行！

每次開發後在 chatroom 用 5–8 行寫「本階段交接總結」，包含：完成了什麼、改了哪些主要檔案、測試結果、下一階段注意點。不要寫長文。


你需要的論文/資料：
- `references/papers/degenerate_sdp_certificate_2405.13625.pdf` — 主論文；CertSDP 的核心數學來源，重點是 degenerate SDP、maximum-rank solution、incidence polynomial system、algebraic exact certificate。
- `references/docs/msolve-tutorial.pdf` — msolve 教學文件；用來了解 polynomial system input/output、real root isolation、RUR / exact algebraic solution workflow。
- `references/repos/hybrid-method/` — 主論文作者的研究代碼；用來參考 paper benchmark、實驗流程與 hybrid method 的原始實作，不要直接照抄成產品架構。
- `references/repos/msolve/` — msolve 原始碼；exact polynomial system backend 的參考與可選編譯來源，CertSDP 核心 verifier 不應依賴它作為可信證明。

--

注意：如果需要下載任何文獻/工具，能有助你的開發，請隨時feel free下載
