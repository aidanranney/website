interface HookContext {
  el: HTMLElement;
  pushEvent(event: string, payload?: object): unknown;
  observer?: IntersectionObserver;
}

interface Hook extends Partial<HookContext> {
  mounted?(this: HookContext): void;
  updated?(this: HookContext): void;
  destroyed?(this: HookContext): void;
}

// Fires a "load-more" event to the LiveView when the target HTMLElement
// intersects 200px from the bottom of the viewport.
export const InfiniteScroll: Hook = {
  mounted(this: HookContext) {
    this.observer = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) this.pushEvent("load-more", {});
      },
      { rootMargin: "0px 0px 200px 0px" },
    );
    this.observer.observe(this.el);
  },
  destroyed(this: HookContext) {
    this.observer?.disconnect();
  },
};

export const Hooks = {
  InfiniteScroll,
};
