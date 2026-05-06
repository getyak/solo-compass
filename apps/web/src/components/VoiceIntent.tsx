"use client";

import { useEffect, useRef, useState } from "react";

interface VoiceIntentProps {
  readonly intent: string | null;
  readonly onIntentChange: (intent: string | null) => void;
}

/**
 * Web Speech API surface (no shipped TS types). We declare the minimum we
 * use — SpeechRecognition + its events. The runtime check at first call
 * gates the whole feature.
 */
interface SpeechRecognitionEventLike {
  results: ArrayLike<{ 0: { transcript: string }; isFinal: boolean }>;
}

interface SpeechRecognitionLike {
  continuous: boolean;
  interimResults: boolean;
  lang: string;
  start: () => void;
  stop: () => void;
  abort: () => void;
  onresult: ((e: SpeechRecognitionEventLike) => void) | null;
  onerror: ((e: { error?: string }) => void) | null;
  onend: (() => void) | null;
}

type SpeechRecognitionCtor = new () => SpeechRecognitionLike;

function getSpeechRecognition(): SpeechRecognitionCtor | null {
  if (typeof window === "undefined") return null;
  const w = window as unknown as {
    SpeechRecognition?: SpeechRecognitionCtor;
    webkitSpeechRecognition?: SpeechRecognitionCtor;
  };
  return w.SpeechRecognition ?? w.webkitSpeechRecognition ?? null;
}

export function VoiceIntent({ intent, onIntentChange }: VoiceIntentProps) {
  const [recording, setRecording] = useState(false);
  const [permissionDenied, setPermissionDenied] = useState(false);
  const [showTextFallback, setShowTextFallback] = useState(false);
  const [textValue, setTextValue] = useState("");
  const recognitionRef = useRef<SpeechRecognitionLike | null>(null);
  const transcriptRef = useRef("");
  const supported = useRef<boolean | null>(null);

  // Lazily init the recogniser the first time the user holds the button.
  function ensureRecognition(): SpeechRecognitionLike | null {
    if (recognitionRef.current) return recognitionRef.current;
    const Ctor = getSpeechRecognition();
    if (!Ctor) {
      supported.current = false;
      setShowTextFallback(true);
      return null;
    }
    supported.current = true;
    const r = new Ctor();
    r.continuous = false;
    r.interimResults = false;
    r.lang = navigator.language || "en-US";
    r.onresult = (e) => {
      const last = e.results[e.results.length - 1];
      if (last && last[0]) {
        transcriptRef.current = last[0].transcript.trim();
      }
    };
    r.onerror = (e) => {
      if (e.error === "not-allowed" || e.error === "service-not-allowed") {
        setPermissionDenied(true);
        setShowTextFallback(true);
      }
      setRecording(false);
    };
    r.onend = () => {
      setRecording(false);
      if (transcriptRef.current.length > 0) {
        onIntentChange(transcriptRef.current);
      }
    };
    recognitionRef.current = r;
    return r;
  }

  function handlePressStart() {
    transcriptRef.current = "";
    const r = ensureRecognition();
    if (!r) return;
    try {
      r.start();
      setRecording(true);
    } catch {
      // start() throws if already running — ignore.
    }
  }

  function handlePressEnd() {
    const r = recognitionRef.current;
    if (!r) return;
    try {
      r.stop();
    } catch {
      // ignore
    }
  }

  function handleTextSubmit(e: React.FormEvent) {
    e.preventDefault();
    const trimmed = textValue.trim();
    if (trimmed.length > 0) {
      onIntentChange(trimmed);
      setTextValue("");
    }
  }

  useEffect(() => {
    return () => {
      try {
        recognitionRef.current?.abort();
      } catch {
        // ignore
      }
    };
  }, []);

  // Detect support up-front so we can render the right control.
  useEffect(() => {
    if (supported.current === null) {
      supported.current = getSpeechRecognition() !== null;
      if (!supported.current) setShowTextFallback(true);
    }
  }, []);

  return (
    <div className="pointer-events-none absolute inset-x-0 bottom-20 z-20 flex flex-col items-center gap-2 px-4">
      {intent && (
        <button
          type="button"
          onClick={() => onIntentChange(null)}
          className="pointer-events-auto max-w-[90vw] rounded-full bg-deep-teal px-4 py-1.5 text-sm text-paper-cream shadow-md ring-1 ring-paper-cream/20 hover:bg-deep-teal/90"
          aria-label={`Clear intent: ${intent}`}
        >
          <span className="mr-2" aria-hidden="true">
            🎯
          </span>
          <span className="truncate align-middle">{intent}</span>
          <span className="ml-2 text-paper-cream/70" aria-hidden="true">
            ×
          </span>
        </button>
      )}

      {!showTextFallback ? (
        <button
          type="button"
          onPointerDown={handlePressStart}
          onPointerUp={handlePressEnd}
          onPointerLeave={recording ? handlePressEnd : undefined}
          onPointerCancel={handlePressEnd}
          aria-label={recording ? "Listening — release to send" : "Hold to speak"}
          aria-pressed={recording}
          className={[
            "pointer-events-auto flex h-14 w-14 items-center justify-center rounded-full",
            "shadow-lg ring-2 ring-paper-cream transition",
            recording ? "scale-110 bg-warm-amber" : "bg-deep-teal hover:scale-105",
            "text-2xl text-paper-cream focus:outline-none focus:ring-4 focus:ring-deep-teal/40",
          ].join(" ")}
        >
          <span aria-hidden="true">{recording ? "●" : "🎙"}</span>
        </button>
      ) : (
        <form onSubmit={handleTextSubmit} className="pointer-events-auto flex w-full max-w-md gap-2">
          <input
            type="text"
            value={textValue}
            onChange={(e) => setTextValue(e.target.value)}
            placeholder={permissionDenied ? "Type instead — mic permission denied" : "What do you feel like?"}
            aria-label="Type what you feel like doing"
            className="flex-1 rounded-full border border-ink-warm/15 bg-paper-cream/95 px-4 py-2 text-sm text-ink-warm shadow focus:border-deep-teal focus:outline-none"
          />
          <button
            type="submit"
            className="rounded-full bg-deep-teal px-4 py-2 text-sm font-medium text-paper-cream shadow hover:bg-deep-teal/90"
          >
            Send
          </button>
        </form>
      )}
    </div>
  );
}
