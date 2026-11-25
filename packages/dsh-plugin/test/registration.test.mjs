import test from 'node:test'
import assert from 'node:assert/strict'

import { apply } from '../index.js'

test('interaction observers register ahead of the desktop answerer', () => {
  const registered = []
  const ctx = {
    on(name, listener, options) {
      registered.push({
        name,
        listener,
        prepend: options === true || (typeof options === 'object' && options?.prepend === true),
      })
      return () => {}
    },
    // Do not run the reconcile/timer effect: this test is only about listener
    // registration, and running it would make a real HTTP request.
    effect() {
      return () => {}
    },
  }

  apply(ctx)

  for (const name of ['approval/request', 'user-questions/request']) {
    const entry = registered.find((item) => item.name === name)
    assert.ok(entry, `${name} is observed`)
    assert.equal(entry.prepend, true, `${name} must prepend or the UI bridge claims it first`)
  }
})
