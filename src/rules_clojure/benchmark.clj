(ns rules-clojure.benchmark
  "Benchmarking harness for gen-build performance.

  Wraps key gen-build functions with timing instrumentation to identify
  bottlenecks in BUILD file generation."
  (:require [clojure.edn :as edn]
            [clojure.string :as str]
            [rules-clojure.fs :as fs]
            [rules-clojure.gen-build :as gen-build]
            [rules-clojure.namespace.find :as find])
  (:import (java.nio.file Path))
  (:gen-class))

;; -- Timing infrastructure ---------------------------------------------------

(def ^:dynamic *timings*
  "Atom collecting [label elapsed-ms] entries during a benchmark run."
  nil)

(defmacro timed
  "Execute body, record elapsed time under label in *timings*, and return result."
  [label & body]
  `(let [start# (System/nanoTime)
         result# (do ~@body)
         elapsed# (/ (double (- (System/nanoTime) start#)) 1e6)]
     (when *timings*
       (swap! *timings* conj {:label ~label :elapsed-ms elapsed#}))
     result#))

(defn- summarize-timings
  "Given a seq of {:label :elapsed-ms} maps, return a summary sorted by total time."
  [timings]
  (let [by-label (group-by :label timings)]
    (->> by-label
         (map (fn [[label entries]]
                {:label label
                 :count (count entries)
                 :total-ms (reduce + (map :elapsed-ms entries))
                 :mean-ms (/ (reduce + (map :elapsed-ms entries)) (count entries))
                 :max-ms (apply max (map :elapsed-ms entries))
                 :min-ms (apply min (map :elapsed-ms entries))}))
         (sort-by :total-ms)
         reverse)))

(defn- print-summary [timings]
  (let [summary (summarize-timings timings)]
    (println)
    (println "=== Benchmark Results ===")
    (println (format "%-35s %8s %8s %8s %8s %5s"
                     "Label" "Total" "Mean" "Min" "Max" "Count"))
    (println (apply str (repeat 80 "-")))
    (doseq [{:keys [label count total-ms mean-ms min-ms max-ms]} summary]
      (println (format "%-35s %7.1fms %7.1fms %7.1fms %7.1fms %5d"
                       label total-ms mean-ms min-ms max-ms count)))
    (println)
    (let [total (reduce + (map :elapsed-ms timings))]
      (println (format "Sum of all timed sections: %.1fms" total)))))

;; -- Instrumented wrappers ----------------------------------------------------

(defn- instrument-var!
  "Replace a var's root binding with a timing wrapper."
  [v label]
  (let [original @v]
    (alter-var-root v (fn [_]
                        (fn [& args]
                          (timed label (apply original args)))))))

(def ^:private instrumented-vars
  "Vars to instrument with labels. Order matters for readability."
  [[#'gen-build/make-basis         "make-basis"]
   [#'gen-build/->jar->lib         "->jar->lib"]
   [#'gen-build/->class->jar       "->class->jar"]
   [#'gen-build/->src-ns->label    "->src-ns->label"]
   [#'gen-build/->dep-ns->label    "->dep-ns->label"]
   [#'gen-build/gen-source-paths   "gen-source-paths"]
   [#'gen-build/gen-source-paths-  "gen-source-paths-"]
   [#'gen-build/gen-dir            "gen-dir"]
   [#'gen-build/ns-rules           "ns-rules"]
   [#'gen-build/get-ns-decl        "get-ns-decl"]
   [#'gen-build/emit-bazel         "emit-bazel"]
   [#'gen-build/source-paths       "source-paths"]
   [#'find/find-namespaces         "find-namespaces"]])

(def ^:private originals (atom {}))

(defn install-instrumentation! []
  (doseq [[v label] instrumented-vars]
    (swap! originals assoc v @v)
    (instrument-var! v label)))

(defn remove-instrumentation! []
  (doseq [[v _] instrumented-vars]
    (when-let [orig (get @originals v)]
      (alter-var-root v (constantly orig))))
  (reset! originals {}))

;; -- Benchmark runners --------------------------------------------------------

(defn bench-srcs
  "Benchmark the `srcs` command with the given opts map.
  Returns {:timings [...] :summary [...]}."
  [opts]
  (binding [*timings* (atom [])]
    (let [wall-start (System/nanoTime)]
      (gen-build/srcs opts)
      (let [wall-ms (/ (double (- (System/nanoTime) wall-start)) 1e6)
            timings @*timings*]
        {:wall-ms wall-ms
         :timings timings
         :summary (summarize-timings timings)}))))

(defn bench-deps
  "Benchmark the `deps` command with the given opts map."
  [opts]
  (binding [*timings* (atom [])]
    (let [wall-start (System/nanoTime)]
      (gen-build/deps opts)
      (let [wall-ms (/ (double (- (System/nanoTime) wall-start)) 1e6)
            timings @*timings*]
        {:wall-ms wall-ms
         :timings timings
         :summary (summarize-timings timings)}))))

(defn run-benchmark
  "Run benchmark N times and print aggregate results.
  opts: same as gen-build srcs opts
  :iterations - number of runs (default 3)
  :command - :srcs or :deps (default :srcs)
  :warmup - number of warmup runs (default 1)"
  [{:keys [iterations command warmup] :or {iterations 3 command :srcs warmup 1} :as opts}]
  (let [bench-opts (dissoc opts :iterations :command :warmup)
        bench-fn (case command :srcs bench-srcs :deps bench-deps)]
    (install-instrumentation!)
    (try
      ;; Warmup
      (when (pos? warmup)
        (println (format "Warming up (%d run%s)..." warmup (if (> warmup 1) "s" "")))
        (dotimes [_ warmup]
          (bench-fn bench-opts))
        (println "Warmup complete."))

      ;; Benchmark runs
      (println (format "Running %d benchmark iteration%s..." iterations (if (> iterations 1) "s" "")))
      (let [results (doall
                     (for [i (range iterations)]
                       (let [result (bench-fn bench-opts)]
                         (println (format "  Run %d: %.1fms wall time" (inc i) (:wall-ms result)))
                         result)))
            all-timings (mapcat :timings results)
            wall-times (map :wall-ms results)]
        (print-summary all-timings)
        (println (format "Wall time: mean=%.1fms min=%.1fms max=%.1fms (over %d runs)"
                         (/ (reduce + wall-times) (count wall-times))
                         (apply min wall-times)
                         (apply max wall-times)
                         (count wall-times)))
        {:wall-times wall-times
         :summary (summarize-timings all-timings)})
      (finally
        (remove-instrumentation!)))))

;; -- CLI entry point ----------------------------------------------------------

(defn -main [& args]
  (let [opts (apply hash-map args)
        opts (into {} (map (fn [[k v]] [(edn/read-string k) v]) opts))
        command (keyword (or (:command opts) "srcs"))
        iterations (Integer/parseInt (str (or (:iterations opts) "3")))
        warmup (Integer/parseInt (str (or (:warmup opts) "1")))
        opts (-> opts
                 (dissoc :command :iterations :warmup)
                 (assoc :command command
                        :iterations iterations
                        :warmup warmup)
                 (update :aliases (fn [aliases]
                                    (when aliases
                                      (-> aliases edn/read-string (#(mapv keyword %))))))
                 (cond->
                     (System/getenv "BUILD_WORKSPACE_DIRECTORY")
                   (assoc :workspace-root (-> (System/getenv "BUILD_WORKSPACE_DIRECTORY") fs/->path))))]
    (run-benchmark opts)
    (shutdown-agents)))
