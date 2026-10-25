# Literature review: the NFSU2 macOS port (2026-10-20)

This document collects the counterparts in the academic and semi-academic
literature of what the project does (statically lifting an x86-32 Win32 game to C
and running it natively on ARM64 macOS; D3D9 → Metal; measurement and graphics
enhancements). The goal is twofold: (1) see where the things we say "we found
ourselves" stand in the literature, (2) pull out techniques we haven't tried yet
that might be useful.

**Method.** A web search per topic; for each source an open-access copy (arXiv,
open proceedings such as USENIX/NDSS, author page, institutional repository) was
looked for. Links were tested with `curl` from this machine on 2026-10-20.

**Markers**

- ✅ open PDF/HTML, link works
- 🔒 no open copy found or not reachable from this machine (DOI/abstract page given)
- 🧭 not academic (blog, talk, tool documentation), but added because the
  literature has a gap there
- ⭐ directly relevant to the project, suggested to read first

Paper summaries were taken from abstract pages and (for some of the ⭐ ones) from
the full text. Numbers for sources whose full text I didn't read are the paper's
own claims.

---

## 0. Short summary: 12 sources to read first

| # | Source | Why |
|---|---|---|
| 1 | ⭐ Arancini (ASPLOS 2026) | An x86 → Arm **hybrid** (static + dynamic) translator; the academic counterpart of our `genexec` approach; its dead flag elimination finding matches our measurement |
| 2 | ⭐ MirrorBall / "No Bit Left Behind" (arXiv, Sep 2026) | Fully static, heuristic-free lifting; solves the pointer/constant problem by brute force; ideal for comparison with our reloc approach |
| 3 | ⭐ Elevator (arXiv, May 2026) | Same group, fully static cross-ISA translation x86-64 → AArch64 |
| 4 | ⭐ Lasagne (PLDI 2022) | Static x86 → Arm translation, LLVM based; memory model |
| 5 | ⭐ BinRec (EuroSys 2020) | Lifting from dynamic traces + recompilation; the dynamic end of the "heuristic-free" line |
| 6 | ⭐ SoK x86 disassembly (S&P 2021) and Andriesse et al. (USENIX Sec 2016) | Systematic evaluation of function / jump table / code-data separation |
| 7 | ⭐ Padding Matters (CODASPY 2025) | Function detection in **PE** files; one of the few works on Windows binaries |
| 8 | ⭐ Testing CPU emulators / Hi-Fi tests for Lo-Fi emulators / MeanDiff | Academic relatives of our Rosetta differential fuzzer |
| 9 | ⭐ Monniaux, "The pitfalls of verifying floating-point computations" | The canonical account of the x87 80-bit ↔ 64-bit double difference |
| 10 | ⭐ STACK (SOSP 2013) + Cerberus/provenance (POPL 2019) | UB traps in generated C (the general case of our strict aliasing bug) |
| 11 | ⭐ HALucinator (USENIX Sec 2020) | "Recognize a library function, replace it with a native equivalent" = the firmware counterpart of our D3DX HLE |
| 12 | ⭐ GraphicsFuzz (OOPSLA 2017) | Validating shader compilers with metamorphic testing; applicable to our vs/ps → MSL translation |

---

## 1. Static binary translation and recompilation (core)

The project's main method. There are two lines in the literature: (a) "binary
lifters" that lift to an IR (mostly LLVM) and recompile, (b) "static binary
translators" that translate from one ISA to another directly. Our lifter lifts to
C and hands it to clang, i.e. a "C-targeted" variant of line (a).

### Classics

- **UQBT: Adaptable Binary Translation at Low Cost.** Cifuentes, Van Emmerik. *IEEE
  Computer* 33(3), 2000. DOI 10.1109/2.825697. 🔒
  A static translator generated from machine descriptions, with interchangeable
  source and target ISAs. The first work to systematically address the core
  problems of static translation (indirect branches, code discovery).
- **DIGITAL FX!32: A Profile-Directed Binary Translator.** Chernoff, Herdeg, Hookway et al.
  *IEEE Micro* 1998. ✅ [PDF](https://web.stanford.edu/class/cs343/resources/fx32.pdf)
  x86 → Alpha on Windows NT. First an interpreter + profile, then static
  translation in the background. **The first commercial example of running Win32
  applications on another ISA;** discusses Win32-specific problems such as
  intercepting `CreateProcess`.
- **Binary Translation Using Peephole Superoptimizers.** Bansal, Aiken. OSDI 2008. ✅
  [PDF](https://db.usenix.org/legacy/events/osdi08/tech/full_papers/bansal/bansal.pdf)
  Learns PowerPC → x86 translation rules automatically with superoptimization; a
  median of 67% of native compiler performance. The idea of learning rules instead
  of writing them by hand is an alternative to our per-instruction lift templates.
- **LLBT: An LLVM-based Static Binary Translator.** Shen, Chen, Hsu, Yang. CASES 2012;
  extended as *A Retargetable Static Binary Translator for the ARM
  Architecture*, ACM TACO 11(2), 2014, DOI 10.1145/2629335. 🔒
  ARM → LLVM IR → various targets. **Treats the whole binary as a single function
  and leaves guest registers to LLVM's global register allocation** (6× faster
  than QEMU, 2.3× faster than HQEMU). Directly related to our cost of carrying the
  `CPU *c` struct across functions (see `LIFTER_EFFICIENCY.md` §3 call model).
- **A Retargetable Hybrid Binary Translation System (HBT).** Shen et al., SIES 2012. ✅
  [PDF](https://people.cs.nycu.edu.tw/~wuuyang/homepage/papers/paper%2045-SIES20120610.pdf)
  Static translation + switching to a dynamic translator on an unfound branch
  target, returning via an address table. The 2012 counterpart of our "address not
  found in dispatch" and `genexec` path.

### LLVM-based lifters

- **McSema: Static Translation of X86 Instructions to LLVM.** Dinaburg, Ruef. REcon 2014
  (talk). 🧭 ✅ [slides](https://www.recon.cx/2014/slides/McSema.pdf)
  Later split off into the Remill instruction-semantics library. No academic paper,
  but most of the validation papers below target McSema.
- **SecondWrite: A Compiler-level IR based Binary Analysis and Rewriting System.** Anand
  et al. EuroSys 2013. ✅ [PDF](https://terpconnect.umd.edu/~barua/anand-EUROSYS-2013.pdf)
  x86 → LLVM IR; recovers the stack frame and local variables, enabling
  optimization. Early work showing our "the stack stays in memory" limit can be
  overcome.
- **rev.ng: A Unified Binary Analysis Framework to Recover CFGs and Function
  Boundaries.** Di Federico, Payer, Agosta. CC 2017. 🔒 (not reachable from this machine)
  [author copy](https://www.nebelwelt.net/files/17CC.pdf)
  17 ISAs with QEMU's front end; noreturn, tail call, context-sensitive CFG
  analyses. Function boundary quality comparable to IDA/angr/BAP.
- **Raising Binaries to LLVM IR with MCTOLL.** Yadavalli, Smith (Microsoft). LCTES 2019
  (WIP). 🔒 [abstract](https://conf.researchr.org/details/LCTES-2019/LCTES-2019-papers/15/Raising-Binaries-to-LLVM-IR-with-MCTOLL-Work-in-progress-)
  x64/Arm32 → LLVM IR using LLVM's own MC layer. Doesn't support SIMD.
- **Instrew: Leveraging LLVM for High Performance Dynamic Binary Instrumentation.**
  Engelke, Schulz. VEE 2020. ✅ [PDF](https://home.cit.tum.de/~engelke/pubs/2003-vee.pdf)
  Lifts machine code directly to LLVM IR and JITs it; 1/5 of Valgrind's overhead.
  Has practical lessons on getting high quality out of lifted code.

### The heuristic-free / full-coverage line (2020 → 2026)

- ⭐ **BinRec: Dynamic Binary Lifting and Recompilation.** Altinay, Nash et al.
  EuroSys 2020. ✅ [PDF](https://download.vusec.net/papers/binrec_eurosys20.pdf)
  Lifts to LLVM IR from **dynamic traces** instead of static disassembly; if an
  untraced path comes up, it goes back and learns it. All of SPEC INT 2006. Should
  be considered together with our coverage tool's "functions that never run"
  measurement.
- ⭐ **Polynima: Practical Hybrid Recompilation for Multithreaded Binaries.** Deshpande,
  Parzefall, Hetzelt, Franz. EuroSys 2024. DOI 10.1145/3627703.3650065 (CC-BY, open
  access; the ACM site rejected automated clients from this machine). 🔒
  An extension of BinRec to multithreaded binaries.
- ⭐ **MirrorBall — No Bit Left Behind: Using Brute-Force Lifting to Achieve Fully
  Static Binary Recompilation.** Huang, Chen, Baron, Franz. arXiv 2609.16423, Sep 2026. ✅
  [arXiv](https://arxiv.org/abs/2609.16423)
  Refuses to separate code from data: builds a superset CFG by **treating every
  byte offset as a possible branch target**; unresolved indirect branches fall into
  a dispatch table; the original binary is embedded as a read-only blob (strings,
  jump tables, vtables stay valid). From the full text: binary size ~74× on
  average, 3.74× slowdown on average on the same ISA, 6.64× for x86-64 → AArch64;
  no multithreading, self-modifying code or C++ exceptions; they say the biggest
  overhead is **keeping register state in thread-local variables (it can't be
  promoted to SSA)**.
  **For us:** our approach is at the opposite end (exact pointer information from
  the reloc table → 96% code coverage, 1.29% uncertainty, close to native speed).
  For the remaining 47 KB of uncertain region, their "try every offset + dispatch"
  idea could be applied at a limited scale. Their register state cost observation
  has the same root as our MEMARG/`restrict` finding.
- ⭐ **Elevator — Deterministic Fully-Static Whole-Binary Translation without
  Heuristics.** Chen, McGowan, Franz. arXiv 2605.08419, May 2026. ✅
  [arXiv](https://arxiv.org/abs/2605.08419)
  x86-64 → AArch64; a separate translation for every plausible interpretation of
  every byte, "code tiles" derived automatically from the ISA definition. Equal to
  or faster than QEMU user mode; the cost is heavy code bloat. According to search
  summaries (I didn't read the full text) the paper has intra-block backward flag
  liveness and proposes **per-flag (instead of whole-EFLAGS) liveness** as future
  work — our flags are already in separate fields.
- **Formally Verified Lifting of C-compiled x86-64 Binaries.** Verbeek, Bockenek, Fu,
  Ravindran. PLDI 2022. ✅ [PDF](https://www.ssrg.ece.vt.edu/papers/pldi22.pdf)
  Proves "sanity" properties such as return address integrity and calling
  convention compliance and lifts covering all paths (over-approximate); exported
  to Isabelle/HOL. ~400K instructions in Xen.

### Memory model and multithreading (x86 TSO → Arm)

The game has threads (audio, loading). On Apple Silicon Rosetta uses the hardware
TSO mode; our native binary doesn't. No race bug has been observed so far, but the
literature shows the scale of this risk:

- ⭐ **Lasagne: A Static Binary Translator for Weak Memory Model Architectures.** Rocha,
  Sprokholt et al. PLDI 2022. 🔒 (the repository wasn't reachable from this machine)
  [St Andrews repository](https://research-repository.st-andrews.ac.uk/handle/10023/25964)
  Static x86 → Arm translation + proven fence placement and redundant fence
  elimination (45.5% fewer fences on average). According to the Arancini paper,
  Lasagne translations are only 2–3× behind native, but it can't translate programs
  heavy in jump tables/function pointers.
- **Risotto: A Dynamic Binary Translator for Weak Memory Model Architectures.**
  Gouicem et al. ASPLOS 2023. DOI 10.1145/3567955.3567962. 🔒 (the TU Delft repository
  rejected automated clients) [TU Delft PDF](https://research.tudelft.nl/files/144252582/3567955.3567962.pdf)
  Finds memory model bugs in QEMU's x86-on-Arm translation and proposes proven
  mapping schemes.
- ⭐ **Arancini: A Hybrid Binary Translator for Weak Memory Model Architectures.**
  Reimers, Sprokholt et al. ASPLOS 2026. ✅
  [PDF](https://www.st.ewi.tudelft.nl/sschakraborty/papers/ASPLOS2026-Arancini.pdf)
  Static + a lightweight runtime + on-demand dynamic translation; a shared IR
  (ArancinIR) models flags and **80-bit x87 registers** directly. Notes from the
  full text:
  - The overwhelming majority of unique instructions are translated ahead of time;
    the dynamic share is at most 2.1%, and the runtime's main job is mapping dynamic
    control flow onto static code. **The same picture as our measurement** (indirect
    call table + `genexec`).
  - **"Dead flag elimination gained little, because LLVM's dead code elimination
    already does something similar."** This matches our intra-function flag
    liveness measurement exactly (flag liveness: no gain, clang already eliminates
    it). Cross-function liveness (FLAGABI for us, −6.9% instructions) isn't in the
    paper.
  - Binding to native libraries (like our replacing CRT/`rep` string operations
    with native equivalents) lowers the overhead from 8.0× → 6.0×; not translating
    `rep` instructions is a significant gain.
  - They leave self-modifying code as an open problem.

---

## 2. Dynamic binary translation (comparison and techniques to borrow)

- **QEMU, a Fast and Portable Dynamic Translator.** Bellard. USENIX ATC 2005 (FREENIX). ✅
  [PDF](https://www.usenix.org/legacy/event/usenix05/tech/freenix/full_papers/bellard/bellard.pdf)
  Lazy flag computation (store the operands + the operation kind, compute on
  demand) is described here and in the QEMU documentation.
- **Dynamo: A Transparent Dynamic Optimization System.** Bala, Duesterwald, Banerjia.
  PLDI 2000. ✅ [PDF](https://www.cse.iitm.ac.in/~krishna/courses/2022/odd-cs6013/BalaDusterwaldBanerjiaPLDI2000.pdf)
  Hot trace selection and re-optimization at run time; the automatic version of our
  profile-guided "move the hot function to native C by hand" (D3DX HLE Stage 4)
  approach.
- **The Transmeta Code Morphing Software.** Dehnert et al. CGO 2003. ✅
  [PDF](https://courses.cs.washington.edu/courses/cse548/08wi/papers/transmeta.pdf)
  Full-system x86 compatibility in software; speculation, rollback, adaptive
  retranslation. One of the best accounts of x86's "real life" corner cases
  (self-modifying code, precise exceptions).
- **HQEMU: A Multi-Threaded and Retargetable Dynamic Binary Translator on Multicores.**
  Hong et al. CGO 2012. 🔒 (the author page rejected automated clients)
  [PDF](https://cs.nthu.edu.tw/~ychung/conference/2012-CGO-HQEMU.pdf)
  QEMU + LLVM; re-optimization with LLVM in a background thread.
- **Virtualization Without Direct Execution or Jitting: Designing a Portable Virtual
  Machine Infrastructure.** Mihocka, Shwartsman. AMAS-BT 2008. ✅
  [PDF](https://bochs.sourceforge.io/Virtualization_Without_Hardware_Final.pdf)
  Bochs's lazy flag representation and fast interpreter design. A direct reference
  for our `genexec` hybrid interpreter.
- ⭐ **ARMing x86 Games: Accelerating Binary Translation Using Software
  Optimizations.** Yen et al. MobiSys 2025. 🔒
  [abstract](https://researchwith.stevens.edu/en/publications/arming-x86-games-accelerating-binary-translation-using-software-o/)
  **Running x86 games on Arm**; uses data flow analysis to find when x86 flags can
  be served by Arm's hardware flags (NZCV); 7–12% FPS in Steam games. Considering
  our lifter can't use NZCV directly because it emits C, generating C patterns that
  clang lowers to `cmp`+`b.cc` would be the static counterpart of this idea.
- **Box64 / FEX-Emu.** 🧭 Box64's 2026 COSCUP talk
  ([abstract](https://pretalx.coscup.org/coscup-2026/talk/PKYW3X/)): flag liveness,
  deferred flag computation, native flag reuse, "wrap first" (bridging to native
  libraries). The FEX blog describes practical optimizations for x87
  ([FEX-2408](https://fex-emu.com/FEX-2408/): detecting 80-bit copies, 2340 → 165
  instructions in one block).
- **Rosetta 2.** 🧭 Apple has no published paper. Independent measurements
  (Anandtech, 2020) say ~78–79% of native. Our comparison is against Wine
  (`WINE_COMPARISON.md`), not Rosetta+Wine.

---

## 3. Disassembly: code discovery, pointer/constant separation, function boundaries, jump tables

The topic the project calls "the hardest problem" (README: *telling a 4-byte
address from a 4-byte number*). Our solution is to parse by hand the reloc data
that is still physically present despite the zeroed reloc directory. I found no
work in the literature that does this (see §13).

- ⭐ **An In-Depth Analysis of Disassembly on Full-Scale x86/x64 Binaries.** Andriesse,
  Chen, van der Veen, Slowinska, Bos. USENIX Security 2016. ✅
  [PDF](https://www.usenix.org/system/files/conference/usenixsecurity16/sec16_paper_andriesse.pdf)
  981 binaries, 9 disassemblers. Inline data and overlapping code are less of a
  problem than believed; **function boundaries are harder than believed.** For
  putting our 96% coverage / 23,274 functions figures in context.
- ⭐ **SoK: All You Ever Wanted to Know About x86/x64 Binary Disassembly But Were Afraid
  to Ask.** Pang et al. IEEE S&P 2021. ✅ [arXiv](https://arxiv.org/abs/2007.14266)
  9 open-source tools, 3,788 binaries. Although all tools use principled algorithms,
  they rely on heavy heuristics for coverage; Ghidra/Dyninst resolve 93% of jump
  tables with ~90% accuracy. To compare our resolving 446 of 763 indirect jumps as
  jump tables against these rates, we first need to work out how many of the
  remaining 317 really are jump tables.
- **Ramblr: Making Reassembly Great Again.** Wang et al. NDSS 2017. ✅
  [PDF](https://sites.cs.ucsb.edu/~vigna/publications/2017_NDSS_Ramblr.pdf)
  A classification of "symbolization" (which immediate is a pointer?) errors. **The
  best account of how hard pointer/constant separation is without relocs.**
- **Superset Disassembly: Statically Rewriting x86 Binaries Without Heuristics
  (Multiverse).** Bauman, Lin, Hamlen. NDSS 2018. ✅
  [PDF](https://www.ndss-symposium.org/wp-content/uploads/2018/02/ndss2018_05A-4_Bauman_paper.pdf)
  Disassembly from every offset; MirrorBall's ancestor.
- **Datalog Disassembly (Ddisasm).** Flores-Montoya, Schulte. USENIX Security 2020. ✅
  [PDF](https://www.usenix.org/system/files/sec20-flores-montoya.pdf)
  Infers code locations, symbols and function boundaries with Souffle Datalog;
  **supports PE and x86-32** and is open source. Could be used to compare our own
  discovery results against an independent tool.
- **ByteWeight: Learning to Recognize Functions in Binary Code.** Bao et al. USENIX
  Security 2014. ✅ [PDF](https://www.usenix.org/system/files/conference/usenixsecurity14/sec14-paper-bao.pdf)
- **Compiler-Agnostic Function Detection in Binaries (Nucleus).** Andriesse,
  Slowinska, Bos. EuroS&P 2017. ✅ [project page and PDF](https://vusec.net/projects/function-detection)
- ⭐ **Padding Matters — Exploring Function Detection in PE Files.** Springer et al.
  CODASPY 2025. ✅ [arXiv](https://arxiv.org/abs/2504.21520)
  Says the literature is ELF-heavy and that function detection **for PE binaries**
  is understudied; measures how alignment padding (int3/nop) misleads tools.
  Directly relevant to the alignment/data classification in our "98.71% explained"
  figure.
- **Recovery of Jump Table Case Statements from Binary Code.** Cifuentes, Van Emmerik.
  *Sci. Comput. Program.* 40(2-3), 2001 (IWPC 1999). 🔒
  Slicing + expression normal form + compiler patterns. The classic reference for
  our jump table resolver.

---

## 4. Instruction semantics and lifter validation (relatives of the Rosetta differential fuzzer)

The project's most productive bug-finding tool: run a lifted instruction against
real x86 code running under Rosetta 2 and compare the state (the Rosetta
differential fuzzer). The counterparts in the literature use a real CPU or another
emulator as the oracle; **I found no work that uses Rosetta as the oracle.**

- ⭐ **Testing CPU Emulators (EmuFuzzer).** Martignoni, Paleari, Fresi Roglia, Bruschi.
  ISSTA 2009; journal version TOSEM 2013. DOI 10.1145/1572272.1572303. 🔒
  Runs the same test input in the emulator and on a physical CPU and compares the
  state; bugs in QEMU, Valgrind, Pin, Bochs. **Exactly the method of our fuzzer.**
- **A Fistful of Red-Pills: How to Automatically Generate Procedures to Detect CPU
  Emulators.** Paleari, Martignoni, Fresi Roglia, Bruschi. WOOT 2009. ✅
  [PDF](https://static.usenix.org/events/woot09/tech/full_papers/paleari.pdf)
  The same group's earlier work automatically generating emulator ↔ real CPU
  differences; differences in hundreds of opcodes.
- ⭐ **Path-Exploration Lifting: Hi-Fi Tests for Lo-Fi Emulators.** Martignoni,
  McCamant, Poosankam, Song, Maniatis. ASPLOS 2012. ✅
  [PDF](https://people.eecs.berkeley.edu/~dawnsong/papers/2012%20Path%20Exploration%20Lifting%20Hi%20Fi%20Tests%20for%20Lo%20Fi%20Emulators.pdf)
  Explores a high-fidelity emulator with symbolic execution and generates test
  inputs with **full per-instruction path coverage** (~610 thousand tests, full
  path coverage for ~95% of instructions). Directly applicable for adding "inputs
  that cover every branch of every instruction" to our random fuzzer.
- **N-Version Disassembly: Differential Testing of x86 Disassemblers.** Paleari et al.
  ISSTA 2010. DOI 10.1145/1831708.1831741. 🔒 Uses the CPU as the reference
  decoder; bugs in all eight disassemblers.
- **Differential Analysis of x86-64 Instruction Decoders (Mishegos).** Woodruff, Carroll,
  Peters. 2021. ✅ [EasyChair preprint](https://easychair.org/publications/preprint/1LHr/open)
  Differences in decoders including Capstone. **Our lifter relies on Capstone;**
  the general case of bugs like the capstone x87 eflags trap.
- ⭐ **Testing Intermediate Representations for Binary Analysis (MeanDiff).** Kim et al.
  ASE 2017. ✅ [PDF](https://softsec.kaist.ac.kr/~soomink/paper/ase17main-mainp491-p.pdf)
  Compares the IRs produced by lifters against each other; 24 semantic bugs in 3
  lifters.
- **Stratified Synthesis: Automatically Learning the x86-64 Instruction Set.** Heule,
  Schkufza, Sharma, Aiken. PLDI 2016. 🔒
  [abstract](https://pldi16.sigplan.org/details/pldi-2016-papers/50/Stratified-Synthesis-Automatically-Learning-the-x86-64-Instruction-Set)
  Learns instruction semantics by synthesis from hardware; dozens of bugs in
  hand-written semantics.
- **A Complete Formal Semantics of x86-64 User-Level Instruction Set Architecture.**
  Dasgupta, Park, Kasampalis, Adve, Roşu. PLDI 2019. ✅
  [PDF](https://fsl.cs.illinois.edu/publications/dasgupta-park-kasampalis-adve-rosu-2019-pldi.pdf)
  3155 instruction variants in the K framework; executable. x87 is out of scope,
  but a reference for integer / flag semantics.
- **Scalable Validation of Binary Lifters.** Dasgupta, Dinesh, Venkatesh, Adve,
  Fletcher. PLDI 2020. DOI 10.1145/3385412.3385964. 🔒 (the PhD thesis with the same
  title at [IDEALS](https://www.ideals.illinois.edu/items/115576) is closed to
  automated clients from this machine)
  Formal translation validation at the single-instruction level; 29 new bugs in
  McSema.
- **ISA Semantics for ARMv8-A, RISC-V, and CHERI-MIPS (Sail).** Armstrong et al. POPL
  2019. ✅ [PDF](https://www.cl.cam.ac.uk/~pes20/sail/sail-popl2019.pdf)
  The formal semantics of the target side (ARM64); we don't need it directly, but
  together with a similar source for x86 (the K semantics) it forms the two ends of
  a "translation validation" chain.

---

## 5. Flags (EFLAGS) and x87

### Flags

- **Register Liveness Analysis for Optimizing Dynamic Binary Translation.** Probst,
  Krall, Scholz. WCRE 2002. 🔒
  [author page](https://www.complang.tuwien.ac.at/andi/papers/wcre_02.html)
  Fast liveness analysis; ~50% fewer redundant stores, 10–30% speedup.
- **Leveraging On-Chip Debug Features for Condition Codes Handling in Dynamic Binary
  Translation.** Salgado et al. SBESC 2014. ✅ [PDF](https://sbesc.lisha.ufsc.br/sbesc2014/dl202)
  A short classification of lazy flag techniques (lazy evaluation, ISA extension,
  hardware support) + a "super lazy" method.
- Arancini (§1), ARMing x86 Games (§2), Bochs (§2), QEMU (§2): the rest of the flag
  discussion is there. **Conclusion:** in compiler-based (LLVM/clang) translators,
  intra-function dead flag elimination can be left to the compiler; the gains come
  from cross-function liveness and from reusing hardware flags.

### x87

- ⭐ **The Pitfalls of Verifying Floating-Point Computations.** Monniaux. ACM TOPLAS 30(3),
  2008. ✅ [arXiv](https://arxiv.org/abs/cs/0701192)
  x87's 80-bit internal precision, double rounding when writing to memory, results
  depending on compiler choices. The basic text for understanding when our "x87 is
  modelled with 64-bit doubles" limit will produce visible differences.
- **Correct Rounding in Double Extended Precision.** LORIA, 2025 (HAL hal-04861251). ✅
  [HAL](https://hal-emse.ccsd.cnrs.fr/LORIA-ALGO/hal-04861251v1)
  Correctly rounded routines for the 80-bit format with double-double arithmetic,
  without needing x87. A viable path if full 80-bit is ever needed (e.g. if some
  physics is found to diverge).
- **I found no academic work that addresses x87 in static translation.** Practical
  sources: the FEX blog (above), felix86 (with 64-bit doubles, "enough for most
  games"), LoongArch's LBT hardware extension (keeps the x87 TOP in hardware). Our
  findings on the FPUSH evaluation order, x87 rounding (`fistp` honoring the RC
  field) and X87OPT (intra-block x87 register allocation, −10.9% instructions) are
  of publishable quality in this gap.

---

## 6. Compiling the generated C: undefined behavior, aliasing, sandboxed memory

Since our lifter emits C, C's own traps intersect directly with the literature.

- ⭐ **Towards Optimization-Safe Systems: Analyzing the Impact of Undefined Behavior
  (STACK).** Wang, Zeldovich, Kaashoek, Solar-Lezama. SOSP 2013. ✅
  [PDF](https://pdos.csail.mit.edu/papers/stack%3Asosp13.pdf)
  "Optimization-unstable" code that the compiler deletes because of UB. The general
  class of our strict aliasing bug (GVN miscompiling lifted code, the root of the
  opt5 difference).
- **Exploring C Semantics and Pointer Provenance (Cerberus).** Memarian et al. POPL
  2019. ✅ [PDF](https://www.cl.cam.ac.uk/~pes20/cerberus/cerberus-popl2019.pdf)
  Pointer provenance and integer ↔ pointer conversions. Clarifies which assumptions
  our code, which sees guest memory as `uint8_t*` + offset, relies on.
- **Not So Fast: Analyzing the Performance of WebAssembly vs. Native Code.** Jangda,
  Powers, Berger, Guha. USENIX ATC 2019. ✅ [arXiv](https://arxiv.org/abs/1901.09056)
  Wasm (base + offset memory, a model very similar to our guest memory) is 45–55%
  slower than native; register pressure and extra address arithmetic are the
  sources. A good template for analyzing where our lifted code loses against native
  code.
- **Segue & ColorGuard: Optimizing SFI Performance and Scalability on Modern
  Architectures.** Narayan et al. ASPLOS 2025. ✅
  [PDF](https://cseweb.ucsd.edu/~dstefan/pubs/narayan:2025:segue.pdf)
  Removes the cost of the base address addition with an x86 segment register
  (11–14%). On ARM64 our `ldr w8, [x_base, w_addr, uxtw]` is already free; but the
  cost of **reloading the base pointer after every write** (which we solved with
  MEMARG) is a problem of the same family.
- **Retrofitting Fine Grain Isolation in the Firefox Renderer (RLBox).** Narayan et al.
  USENIX Security 2020. ✅ [arXiv](https://arxiv.org/abs/2003.00572)
  Wasm → C → native with wasm2c; "translation using C as the target language" in
  production.

---

## 7. The operating system / API layer and high-level emulation (HLE)

- **Rethinking the Library OS from the Top Down (Drawbridge).** Porter, Boyd-Wickizer,
  Howell, Olinsky, Hunt. ASPLOS 2011. ✅ [PDF](https://www.cs.unc.edu/~porter/pubs/p291-porter.pdf)
  Runs Windows 7 as a library OS on top of a small kernel interface (threads,
  virtual memory, I/O streams); DirectX included. **The academic reference for which
  abstractions our hand-written Win32 layer could be reduced to.**
- ⭐ **HALucinator: Firmware Re-hosting Through Abstraction Layer Emulation.** Clements
  et al. USENIX Security 2020. ✅ [PDF](https://www.usenix.org/system/files/sec20-clements.pdf)
  Matches HAL library functions in the binary and substitutes generic
  implementations; the paper explicitly calls this "high-level emulation (HLE)".
  **The direct counterpart of our D3DX9 HLE work (`D3DX_HLE.md`);** the library
  matching part could be applied to recognize statically linked D3DX/CRT functions
  automatically.
- **Statically linked library recognition (FLIRT alternatives).**
  - Arutunian, Aslanyan. *Proceedings of ISP RAS* 38(4), 2026 — embedded library
    recognition with a program dependence graph + call graph (91% precision, 99%
    recall on average). ✅
    [PDF](https://ispras.ru/proceedings/docs/2026/38/4-1/isp_38_2026_4_89.pdf)
  - Carrillo-Mondéjar, Rodríguez. *MANTILLA*, Future Generation Computer Systems 2025,
    DOI 10.1016/j.future.2024.107602. 🔒
  The game statically links the MSVC CRT and D3DX9; recognizing them and replacing
  them with native equivalents gives both speed (the "native library" gain in
  Arancini) and correctness.
- **Wine.** 🧭 I found no peer-reviewed architecture/performance paper. Our
  `WINE_COMPARISON.md` measurement (native 119 fps in a race, Wine 10–15 fps) is the
  only data point in this gap.

---

## 8. Graphics API and shader translation (D3D9 → Metal, vs/ps 1.x–2.x → MSL)

**I found no academic paper addressing D3D9 → Metal or DXBC → MSL translation.**
The field has progressed entirely through industry and open-source tools (DXVK,
wined3d, MoltenVK, SPIRV-Cross, dxil-spirv). On the validation side, however,
there is strong academic work:

- ⭐ **Automated Testing of Graphics Shader Compilers (GLFuzz → GraphicsFuzz).**
  Donaldson, Evrard, Lascu, Thomson. OOPSLA 2017. ✅
  [PDF](https://www.doc.ic.ac.uk/~afd/papers/2017/OOPSLA.pdf)
  Generates shader variants with semantics-preserving transformations and finds
  compiler bugs from image differences; 60+ bugs in 17 GPUs/drivers. **Applicable to
  our vs/ps → MSL translation:** transforming the game's own shaders in
  semantics-preserving ways and comparing the output after translation would
  systematically find bugs like the MSL write mask, the expp skinning and the D3D9
  color clamping bugs.
- **Test-Case Reduction and Deduplication Almost for Free with Transformation-Based
  Compiler Testing (spirv-fuzz).** Donaldson et al. PLDI 2021. ✅
  [PDF](https://www.doc.ic.ac.uk/~afd/homepages/papers/pdfs/2021/PLDI.pdf)
  Automatically shrinks the bug-triggering transformation sequence.
- 🧭 **MoltenVK: Application Portability with Vulkan on Metal.** Vulkanised 2023. ✅
  [slides](https://dev.vulkan.org/user/pages/09.events/vulkanised-2023/vulkanised_2023_moltenvk_application_portability_with_vulkan_on_metal.pdf)
  The unavoidable memory/performance cost of a Vulkan → Metal layer; "binary ports
  of DirectX origin" are listed among the cases that hit the performance limit. The
  rationale for our choice of going D3D9 → Metal directly (no intermediate layer).
- 🧭 **My personal hell of translating DXIL to SPIR-V.** Themaister (vkd3d-proton), 2021. ✅
  [blog](https://themaister.net/blog/2021/09/05/my-personal-hell-of-translating-dxil-to-spir-v-part-1/)
  The compiler-theory side of translating shader intermediate languages;
  unstructured control flow etc.
- **Primary specifications** (not papers, but the source of truth): Microsoft
  "Directly Mapping Texels to Pixels (Direct3D 9)" (the half-pixel rule — our D3D9
  half-pixel fix), the D3D9 shader model 1.x–3.0 reference documentation, Apple
  Metal Shading Language Specification.

---

## 9. Graphics enhancements (HD build: SSR, ray-traced reflections, filtering)

- **Efficient GPU Screen-Space Ray Tracing.** McGuire, Mara. *JCGT* 3(4), 2014. ✅
  [PDF](https://jcgt.org/published/0003/04/04/paper.pdf)
  Ray marching in the depth buffer with perspective-correct DDA; the standard SSR
  reference.
- **An Adaptive Acceleration Structure for Screen-Space Ray Tracing.** Widmer et al.
  HPG 2015. ✅ [PDF](https://research.nvidia.com/sites/default/files/pubs/2015-08_An-Adaptive-Acceleration/AcceleratedSSRT_HPG15.pdf)
  SSR accelerated with hierarchical depth.
- **Hybrid Rendering for Real-Time Ray Tracing (PICA PICA).** Barré-Brisebois et al.
  *Ray Tracing Gems*, chapter 25, 2019 (the book is open access). ✅
  [book](https://link.springer.com/book/10.1007/978-1-4842-4427-2) ·
  [EA SEED](https://ea.com/seed/news/hybrid-rendering-for-real-time-ray-tracing)
  A hybrid raster + ray tracing pipeline, glossy reflections. The closest source to
  our half-resolution RT reflection + G-buffer separation design. *Ray Tracing Gems
  II* (2021) is also open access.
- **Spatiotemporal Variance-Guided Filtering (SVGF).** Schied et al. HPG 2017. ✅
  [PDF](https://cg.ivd.kit.edu/publications/2017/svgf/svgf_preprint.pdf)
  Temporal accumulation from 1 sample per pixel + a variance-guided filter. A
  candidate for upscaling the half-resolution reflection without noise.
- For the poisoned acceleration structure (NaN/far vertices poisoning the
  acceleration structure) I found no direct paper; *Ray Tracing Gems* chapter 6 ("A
  Fast and Robust Method for Avoiding Self-Intersection") and the chapters on BVH
  robustness are the closest sources.

---

## 10. Measurement method, performance and energy

- ⭐ **Producing Wrong Data Without Doing Anything Obviously Wrong!** Mytkowicz, Diwan,
  Hauswirth, Sweeney. ASPLOS 2009. ✅ [project page](https://sape.inf.usi.ch/publications/asplos09)
  Innocent changes such as environment variable size or link order bias
  measurements. The theoretical framework for our findings on measurement method (a
  single run is 7% noisy), the frame limiter masking measurements, and the
  DUMPFRAME measurement artifact; even the link order of the 128 shards could move
  the result.
- **Rigorous Benchmarking in Reasonable Time.** Kalibera, Jones. ISMM 2013. ✅
  [Kent repository](https://kar.kent.ac.uk/33611/)
  A model computing how many repetitions are needed at which level (build / run /
  iteration). For justifying the repetition counts in our A/B measurements (ABTEST,
  alternating runs).
- **Apple vs. Oranges: Evaluating the Apple Silicon M-Series SoCs for HPC Performance and
  Efficiency.** Hübner et al. arXiv 2502.05317, 2025. ✅ [arXiv](https://arxiv.org/abs/2502.05317)
  Power measurement on M1–M4 with `powermetrics`. Note: `powermetrics` is a
  model-based estimate, not a wall measurement; relative comparisons are more
  reliable. Consistent with our energy measurement and GPU energy A/B methods.
- **RAVEN: Perception-aware Optimization of Power Consumption for Mobile Games.** MobiCom
  2017. 🔒 21.8% energy savings on average by skipping perceptually identical frames.
- **Yan et al., HotPower 2015.** ✅
  [PDF](https://engineering.purdue.edu/~hotpower/HotPower_2015_paper_6.pdf)
  40 mobile games; a constant high frame rate is wasteful in static scenes, dynamic
  frame rate scaling. The same idea as our HD driving GPU ceiling observation ("a
  stationary car, GPU 8 W").

---

## 11. Language-model-based translation (new, experimental)

- **From CISC to RISC: Language-Model Guided Assembly Transpilation (CRT).** Heakl et
  al. arXiv 2411.16341, 2024. ✅ [arXiv](https://arxiv.org/abs/2411.16341)
  x86 → ARM assembly; ~79% accuracy. Not suitable for a game that needs
  whole-program correctness, but could be considered for draft translations of the
  rare instructions still left as "traps" (400 of them for us).
- **Guaranteed Guess: A Language Modeling Approach for CISC-to-RISC Transpilation with
  Testing Guarantees.** arXiv 2506.14606, 2025. ✅ [arXiv](https://arxiv.org/abs/2506.14606)
  Securing language model output with testing; our fuzzer already exists as such a
  guarantee layer.

---

## 12. Game preservation and the legal framework

- **Making videogame history: videogame preservation and copyright law.** Y. Lee.
  *Interactive Entertainment Law Review* 1(2), 2018. ✅ [White Rose repository](https://eprints.whiterose.ac.uk/137835/)
  Reverse engineering, decompilation and preservation exceptions. The legal
  background of the README's decision that "game code and assets are not
  distributed".
- I found **no peer-reviewed paper** on porting games with static recompilation
  (N64Recomp, XenonRecomp, xboxrecomp, M-HT/SR); the field moves entirely through
  community projects.

---

## 13. What I didn't find in the literature (possible contributions of the project)

At the end of the review, work done in the project for which I found no
counterpart in the literature:

1. **Recovering reloc data that is physically present despite a zeroed reloc
   directory and using it for pointer/constant separation.** The literature either
   assumes relocs *exist* (Ramblr/Ddisasm treat them as auxiliary information) or
   that there are none at all (Multiverse, MirrorBall). The "looks deleted but is
   still there" case isn't addressed.
2. **A differential instruction fuzzer that uses Rosetta 2 as the oracle.**
   EmuFuzzer and Mishegos use a physical x86 CPU; building the same method with
   Rosetta on Apple Silicon without x86 hardware is new.
3. **Handling x87 in static translation** (stack evaluation order, `fistp` honoring
   the RC field, intra-block x87 register allocation). No academic work; no sources
   apart from the FEX/felix86 blogs.
4. **End-to-end static recompilation of a 23-thousand-function Win32 + D3D9 3D
   game** and its performance/energy measured against Wine. Lasagne/Arancini/
   MirrorBall use benchmark suites such as SPEC and Phoenix; no real interactive
   application.
5. **Validating the D3D9 shader bytecode → MSL translation** (image differences + a
   Windows reference). The GraphicsFuzz method exists but hasn't been applied to
   API/bytecode translation.

These five look like enough material for a workshop paper (e.g. the
AMAS-BT/VEE/CGO workshops, or the "Binary Analysis Research" NDSS workshop).

---

## 14. Concrete experiments suggested by the literature (in order of importance)

1. **MirrorBall-style superset lifting for the remaining uncertain bytes** (only in
   47 KB / 1,546 blocks): try every offset + a dispatch table. Makes the `genexec`
   path even rarer.
2. **Path-coverage-guided input generation for the fuzzer** (Hi-Fi/Lo-Fi): values
   covering every branch of every instruction instead of random ones (overflow
   boundaries, division by zero, x87 special values). Especially while enabling the
   400 "trap" instructions.
3. **Metamorphic testing for shader translation** (GraphicsFuzz): applying
   semantics-preserving transformations to the game's shaders and comparing the Metal
   output.
4. **Automatic recognition of statically linked CRT/D3DX functions**
   (HALucinator's matching step / FLIRT-style signatures) and replacing them with
   native equivalents; our counterpart of the "native library" gain in Arancini.
5. **Hardware flag reuse** (ARMing x86 Games): emitting `cmp`/`jcc` pairs as C
   patterns that clang reduces to a single `cmp` + `b.cc`.
6. **Randomizing link order in measurements** (Mytkowicz): separating an
   optimization's gain from layout effects by varying the shard link order.
7. **Memory model checking in multithreaded parts** (Lasagne/Risotto): whether the
   data shared by the audio and loading threads needs a TSO assumption.

---

## Access note

Most of the 🔒 sources are at ACM/IEEE; for these no author page or institutional
repository was found, or they weren't reachable from this machine (some
repositories reject automated clients; they can be opened from a browser). No PDF
was downloaded into the repository.
