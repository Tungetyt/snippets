import {produce, Draft} from 'immer';

type Primitive = string | number | boolean | symbol | null | undefined;

type ArrayKey = number;

type PathImpl<K extends string | number, V> = V extends Primitive
  ? `${K}`
  : `${K}` | `${K}.${Paths<V>}`;

type TuplePaths<T extends readonly [unknown, ...unknown[]]> = {
  [K in Extract<keyof T, `${number}`>]: PathImpl<K & string, T[K]>;
}[Extract<keyof T, `${number}`>];

type ObjectPaths<T> = {
  [K in keyof T]: PathImpl<K & string, T[K]>;
}[keyof T];

type Paths<T> = T extends readonly [unknown, ...unknown[]]
  ? TuplePaths<T>
  : T extends readonly unknown[]
  ? PathImpl<ArrayKey, T[number]>
  : T extends object
  ? ObjectPaths<T>
  : '';

  type PathValue<T, P extends Paths<T>> = P extends `${infer Key}.${infer Rest}`
  ? Key extends keyof T
    ? Rest extends Paths<T[Key]>
      ? PathValue<T[Key], Rest>
      : never
    : T extends readonly unknown[]
    ? Key extends `${number}`
      ? Rest extends Paths<T[number]>
        ? PathValue<T[number], Rest>
        : never
      : never
    : never
  : P extends keyof T
  ? T[P]
  : T extends readonly unknown[]
  ? P extends `${number}`
    ? T[number]
    : never
  : never;

type SetContent<S> = S extends Set<infer U> ? U : never;

interface StateManagerOptions {
  rootElement?: HTMLElement;
  mutationObserverOptions?: MutationObserverInit;
}

class StateManager<T extends object> extends EventTarget {
  private state: T;
  private rootElement: HTMLElement;
  private mutationObserverOptions: MutationObserverInit;

  public static Events = new Set(['update', 'delete', 'add'] as const);

  constructor(initialState: T, options: StateManagerOptions = {}) {
    super();
    this.state = this.deepFreeze(structuredClone(initialState)) as T;

    // Set rootElement for MutationObserver, default to document.body
    this.rootElement = options.rootElement || document.body;

    // Set MutationObserver options, default to observing subtree
    this.mutationObserverOptions = options.mutationObserverOptions || {
      childList: true,
      subtree: true,
      attributes: true,
    };
  }

  private deepFreeze(obj: unknown): unknown {
    if (obj && typeof obj === 'object' && !Object.isFrozen(obj)) {
      Object.freeze(obj);
      Object.getOwnPropertyNames(obj).forEach((prop) => {
        const propValue = (obj as Record<string, unknown>)[prop];
        if (
          Object.prototype.hasOwnProperty.call(obj, prop) &&
          propValue !== null &&
          (typeof propValue === 'object' || typeof propValue === 'function')
        ) {
          this.deepFreeze(propValue);
        }
      });
    }
    return obj;
  }

  public get(): T {
    return this.state;
  }

  public set<
    P extends Paths<T>,
    E extends SetContent<typeof StateManager.Events>
  >(path: P, value: PathValue<T, P>, eventName: E): void {
    // Validate event name
    if (!StateManager.Events.has(eventName)) {
      throw new Error(`Invalid event name: ${eventName}`);
    }

    // Create new state using Immer
    const newState = produce(this.state, (draft: Draft<T>) => {
      this.setValueAtPath(draft, path, value);
    });

    // Deep freeze newState
    this.state = this.deepFreeze(newState) as T;

    // Emit event
    this.emitEvent(eventName, path);
  }

  private setValueAtPath(obj: unknown, path: string, value: unknown): void {
    const keys = path.split('.');
    let current = obj as Record<string | number, unknown>;
    for (let i = 0; i < keys.length - 1; i++) {
      let key: string | number | undefined = keys[i];
      if (!key) {
        throw new Error("Expected key to be present.")
      }
      key = isNaN(Number(key)) ? key : Number(key);
      if (!(key in current)) {
        throw new Error(`Invalid path: Property '${key}' does not exist.`);
      }
      const next = current[key];
      if (typeof next !== 'object' || next === null) {
        throw new Error(`Invalid path: '${key}' is not an object.`);
      }
      current = next as Record<string | number, unknown>;
    }
    const lastKey = keys[keys.length - 1];
    if (!lastKey) {
      throw new Error("Expected lastKey to be present.")
    }
    let finalKey: string | number = lastKey;
    finalKey = isNaN(Number(finalKey)) ? finalKey : Number(finalKey);
    current[finalKey] = value;
  }

  private emitEvent(eventName: string, path: string): void {
    const event = new CustomEvent(eventName, {
      detail: { state: this.state, path },
    });
    this.dispatchEvent(event);
  }

  // Subscription mechanism with automatic unsubscription
  public subscribe<
    E extends SetContent<typeof StateManager.Events>
  >(
    eventName: E,
    listener: (event: CustomEvent) => void,
    element?: HTMLElement
  ): void {
    const handler = listener as EventListener;

    // Bind the event listener to the StateManager
    this.addEventListener(eventName, handler);

    if (element) {
      // Create a MutationObserver to watch for the element's removal or movement
      const observer = new MutationObserver(() => {
        // Check if the element is still connected to the DOM
        if (!element.isConnected) {
          // Element has been removed from the DOM
          this.removeEventListener(eventName, handler);
          observer.disconnect();
        }
      });

      // Start observing the rootElement for changes
      observer.observe(this.rootElement, this.mutationObserverOptions);
    }
  }
}

// Example usage:

type State = {
  abc: number;
  cde: number;
  fgh: { ijk: { lmn: number; opr: number[] } };
};

const initialState: State = {
  abc: 123,
  cde: 987,
  fgh: { ijk: { lmn: 765, opr: [864, 543] } },
};

// Optionally specify a root element and observer options
const rootElement = document.getElementById('app') || document.body;

const stateManager = new StateManager(initialState, {
  rootElement,
  mutationObserverOptions: {
    childList: true,
    subtree: true,
    attributes: false, // Can customize as needed
  },
});

// Suppose we have a DOM element that wants to subscribe
const myElement = document.createElement('div');
document.body.appendChild(myElement);

const listener = (event: CustomEvent) => {
  console.log('State updated:', event.detail);
};

// Subscribe with automatic unsubscription when myElement is removed
stateManager.subscribe('update', listener, myElement);

// Updating the state before removing the element will trigger the listener
stateManager.set('abc', 456, 'update'); // Listener will be called

// Move the element within the DOM
const newParent = document.createElement('div');
document.body.appendChild(newParent);
newParent.appendChild(myElement);

// The listener remains subscribed because the element is still connected

// Remove the element from the DOM
newParent.removeChild(myElement);

// Updating the state after the element is removed won't trigger the listener
stateManager.set('abc', 789, 'update'); // Listener won't be called
