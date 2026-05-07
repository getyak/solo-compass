"use client";

import { dismissIOSPrompt } from "@/lib/checkin-store";

interface IOSPromptProps {
  readonly onDismiss: () => void;
}

export function IOSPrompt({ onDismiss }: IOSPromptProps) {
  function handleDismiss() {
    dismissIOSPrompt();
    onDismiss();
  }

  return (
    <div className="fixed top-0 inset-x-0 z-50 px-4 pt-safe-top pb-3 bg-paper-cream/95 backdrop-blur-sm border-b border-ink-warm/10 shadow-md">
      <div className="max-w-md mx-auto">
        <p className="text-xs text-ink-warm/60 mb-2 text-center">
          The iOS app does this automatically with background GPS
        </p>
        <div className="flex gap-2">
          <a
            href="https://apps.apple.com/app/solo-compass"
            target="_blank"
            rel="noopener noreferrer"
            className="flex-1 rounded-xl bg-deep-teal py-2.5 text-sm font-semibold text-paper-cream text-center transition hover:bg-deep-teal/90"
          >
            Get the free app
          </a>
          <button
            type="button"
            onClick={handleDismiss}
            className="flex-1 rounded-xl bg-ink-warm/10 py-2.5 text-sm font-semibold text-ink-warm text-center transition hover:bg-ink-warm/15"
          >
            Keep using web
          </button>
        </div>
      </div>
    </div>
  );
}
