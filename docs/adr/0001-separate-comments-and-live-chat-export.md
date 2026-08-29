# Keep comments and live chat export separate from download

ClipFetch treats Comments and Live Chat Export as its own operation rather than a Download because it selects one author's entries, may translate them through OpenRouter, and produces text files instead of an MP4. It shares the single Active Operation slot with Inspection and Download so cancellation and interface state remain serial, without a queue or parallel lifecycles.
