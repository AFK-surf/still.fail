// TeX delimiters at the Markdown tokenizer, so code spans/fences and escaped backslashes stay untouched.
// Reuse the math extension's nodes and $$ block parser; dollars in prose are always ordinary text.
import { math } from "micromark-extension-math";
import type { Construct, Extension, State } from "micromark-util-types";

// 92 is a backslash; 40/41 are parentheses, 91/93 square brackets.
export const mathSyntax: Extension = {
  flow: { ...math().flow, 92: bracket(91, 93, true) },
  text: { 92: bracket(40, 41, false) },
};

function bracket(open: number, close: number, block: boolean): Construct {
  return {
    concrete: block,
    tokenize(effects, ok, nok) {
      const self = this;
      return start;
      function start(code: number | null): State | undefined {
        effects.enter("mathText");
        effects.enter("mathTextSequence");
        effects.consume(code);
        return opening;
      }
      function opening(code: number | null): State | undefined {
        if (code !== open) return nok(code);
        effects.consume(code);
        effects.exit("mathTextSequence");
        return block && self.interrupt ? ok : data;
      }
      function data(code: number | null): State | undefined {
        if (code === null) return nok(code);
        // Micromark represents LF, CR and CRLF as -4, -5 and -3.
        if (code <= -3) {
          effects.enter("lineEnding");
          effects.consume(code);
          effects.exit("lineEnding");
          return data;
        }
        if (code === 92) return effects.check({ tokenize: ending }, end, slash)(code);
        effects.enter("mathTextData");
        return content(code);
      }
      function content(code: number | null): State | undefined {
        if (code === null || code <= -3 || code === 92) {
          effects.exit("mathTextData");
          return data(code);
        }
        effects.consume(code);
        return content;
      }
      // A TeX escape (including \\) consumes its next character, so \\) is not a closing delimiter.
      function slash(code: number | null): State | undefined {
        effects.enter("mathTextData");
        effects.consume(code);
        return escaped;
      }
      function escaped(code: number | null): State | undefined {
        if (code === null || code <= -3) return content(code);
        effects.consume(code);
        return content;
      }
      function ending(e: typeof effects, yes: typeof ok, no: typeof nok): State {
        return (code) => { e.consume(code); return (next) => next === close ? yes(next) : no(next); };
      }
      function end(code: number | null): State | undefined {
        effects.enter("mathTextSequence");
        effects.consume(code);
        return closing;
      }
      function closing(code: number | null): State | undefined {
        effects.consume(code);
        effects.exit("mathTextSequence");
        effects.exit("mathText");
        return block ? after : ok;
      }
      function after(code: number | null): State | undefined {
        if (code === 32 || code === -2 || code === -1) { effects.consume(code); return after; }
        return code === null || code === -5 || code === -4 || code === -3 ? ok(code) : nok(code);
      }
    },
  };
}
