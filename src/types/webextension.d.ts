// The slice of the WebExtension API this extension touches. See docs/architecture.md.

declare namespace WebExtension {
  interface Tab {
    readonly id?: number;
  }

  interface InjectionResult {
    readonly result?: unknown;
  }

  interface ScriptInjection {
    readonly target: { readonly tabId: number };
    readonly files: readonly string[];
  }
}

declare const browser: {
  readonly action: {
    readonly onClicked: {
      addListener(callback: (tab: WebExtension.Tab) => void): void;
    };
  };
  readonly scripting: {
    executeScript(
      injection: WebExtension.ScriptInjection,
    ): Promise<readonly WebExtension.InjectionResult[]>;
  };
};
