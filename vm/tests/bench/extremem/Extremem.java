// Extremem (https://github.com/corretto/heapothesys/tree/master/Extremem, Apache-2.0, see NOTICE) as a
// discrete-event simulation in virtual time: the Java twin of Extremem.st, with Extremem's own data structures.
// Same random numbers, same events, same checksum. Usage: java Extremem.java [name=value ...]
import java.lang.management.GarbageCollectorMXBean;
import java.lang.management.ManagementFactory;
import java.util.*;

public class Extremem {
  static final class Rnd {
    long seed;
    final long multiplier;
    Rnd(long seed) { this(seed, 48271); }
    Rnd(long seed, long multiplier) { this.seed = seed; this.multiplier = multiplier; }
    long next() { seed = seed * multiplier % 2147483647L; return seed; }
    int nextInt(int n) { return (int) (next() % n); }
    double nextFloat() { return next() / 2147483647.0; }
  }

  static final class Config {
    long randomSeed = 42;
    int dictionarySize = 25000, numProducts = 20000, productNameLength = 5, productDescriptionLength = 24;
    int numCustomers = 10000, customerThreads = 1440;
    long customerPeriod = 240_000_000L, customerThinkTime = 200_000_000L;
    int keywordSearchCount = 5;
    boolean allowAnyMatch = true;
    int productReviewLength = 32, selectionCriteriaCount = 8;
    double buyThreshold = 0.4, saveForLaterThreshold = 0.4;
    int serverThreads = 10;
    long serverPeriod = 500_000L;
    int salesTransactionQueueCount = 10, browsingHistoryQueueCount = 10;
    long browsingExpiration = 600_000_000L, customerReplacementPeriod = 60_000_000L;
    int customerReplacementCount = 16;
    long productReplacementPeriod = 90_000_000L;
    int productReplacementCount = 64;
    int simulationMinutes = 10, warmupMinutes = 2;
    String[] words;

    void set(String key, String value) throws ReflectiveOperationException {
      java.lang.reflect.Field f = Config.class.getDeclaredField(key);
      if (f.getType() == boolean.class) f.setBoolean(this, Boolean.parseBoolean(value));
      else if (f.getType() == int.class) f.setInt(this, Integer.parseInt(value));
      else if (f.getType() == long.class) f.setLong(this, Long.parseLong(value));
      else throw new IllegalArgumentException("Unknown Extremem parameter: " + key);
    }

    void makeWords(Rnd random) {
      String letters = "eeeeeeeeeeeeettttttttttaaaaaaaaaooooooooiiiiiiiinnnnnnnnsssssssshhhhhhrrrrrrrddddlllllcccuuummmwwffggyyppbbvkjxqz";
      words = new String[dictionarySize];
      for (int i = 0; i < dictionarySize; i++) {
        int length = 2 + random.nextInt(5) + random.nextInt(6);
        char[] word = new char[length];
        for (int j = 0; j < length; j++) word[j] = letters.charAt(random.nextInt(letters.length()));
        words[i] = new String(word);
      }
    }

    String arbitraryWord(Rnd random) { return words[random.nextInt(words.length)]; }

    String randomString(int length, Rnd random) {
      String result = "";
      for (int i = 0; i < length; i++) {
        if (result.length() > 0) result += " ";
        result += arbitraryWord(random);
      }
      return result;
    }

    String[] randomKeywords(int count, Rnd random) {
      String[] result = new String[count];
      for (int i = 0; i < count; i++) {
        String word;
        boolean dependent;
        do {
          word = arbitraryWord(random);
          dependent = false;
          for (int j = 0; j < i; j++) if (result[j].equals(word)) dependent = true;
        } while (dependent);
        result[i] = word;
      }
      return result;
    }
  }

  static final class Product {
    final long id;
    final String name, description;
    boolean available = true;
    Product(long id, String name, String description) { this.id = id; this.name = name; this.description = description; }
  }

  static final class Customer {
    final String name;
    final long id;
    long purchaseHash;
    boolean deceased;
    int fsfl, csfl;
    BrowsingHistory[] sflq = new BrowsingHistory[8];
    Customer(String name, long id) { this.name = name; this.id = id; }

    void transactSale(SalesTransaction sale, long releaseTime) {
      purchaseHash += ((releaseTime / 1_000_000) & (releaseTime % 1_000_000 * 1000)) + sale.product.id;
    }

    void addSaveForLater(BrowsingHistory h) {
      if (deceased) {
        h.queue.dequeue(h);
        return;
      }
      if (csfl >= sflq.length) {
        BrowsingHistory[] expanded = new BrowsingHistory[2 * sflq.length];
        for (int i = 0; i < csfl; i++) {
          expanded[i] = sflq[fsfl++];
          if (fsfl == sflq.length) fsfl = 0;
        }
        sflq = expanded;
        fsfl = 0;
      }
      sflq[(fsfl + csfl++) % sflq.length] = h;
    }

    void retireOneSaveForLater(BrowsingHistory h) {
      int index = 0;
      for (int i = 0; i < csfl; i++) {
        index = (fsfl + i) % sflq.length;
        if (sflq[index] == h) break;
      }
      while (index != fsfl) {
        int prior = index - 1;
        if (prior < 0) prior = sflq.length - 1;
        sflq[index] = sflq[prior];
        index = prior;
      }
      sflq[fsfl++] = null;
      csfl--;
      if (fsfl == sflq.length) fsfl = 0;
    }

    Product[] allSavedForLater() {
      Product[] result = new Product[csfl];
      for (int i = 0, index = fsfl; i < csfl; i++) {
        result[i] = sflq[index++].product;
        if (index == sflq.length) index = 0;
      }
      return result;
    }

    void prepareForDemise() {
      deceased = true;
      int index = fsfl;
      for (int i = 0; i < csfl; i++) {
        BrowsingHistory h = sflq[index];
        h.queue.dequeue(h);
        sflq[index++] = null;
        if (index >= sflq.length) index = 0;
      }
      fsfl = csfl = 0;
    }
  }

  static final class SalesTransaction {
    final Customer customer;
    final Product product;
    final String review;
    SalesTransaction next;
    SalesTransaction(Customer c, Product p, String review) { customer = c; product = p; this.review = review; }
  }

  static final class BrowsingHistory {
    final Customer customer;
    final Product product;
    final long expiration;
    final BrowsingQueue queue;
    BrowsingHistory next, prev;
    BrowsingHistory(Customer c, Product p, long expiration, BrowsingQueue q) {
      customer = c; product = p; this.expiration = expiration; queue = q;
    }
  }

  static final class SalesQueue {
    SalesTransaction head, tail;
    void enqueue(SalesTransaction s) {
      s.next = null;
      if (head == null) head = tail = s;
      else { tail.next = s; tail = s; }
    }
    SalesTransaction dequeue() {
      if (head == null) return null;
      SalesTransaction result = head;
      head = head.next;
      result.next = null;
      return result;
    }
  }

  static final class BrowsingQueue {
    BrowsingHistory head;
    void enqueue(BrowsingHistory h) {
      if (head == null) { h.next = h.prev = h; head = h; }
      else { h.prev = head.prev; h.next = head; h.prev.next = h; h.next.prev = h; }
    }
    BrowsingHistory pullIfExpired(long now) {
      if (head == null) return null;
      BrowsingHistory candidate = head;
      if (candidate.expiration > now) return null;
      if (candidate.next == candidate) { head = null; candidate.next = candidate.prev = null; }
      else { head = head.next; head.prev = candidate.prev; head.prev.next = head; head.next.prev = head; }
      return candidate;
    }
    void dequeue(BrowsingHistory h) {
      if (h.next == h) head = null;
      else {
        h.next.prev = h.prev;
        h.prev.next = h.next;
        if (head == h) head = h.next;
      }
      h.next = h.prev = null;
    }
  }

  static final class Customers {
    final Config config;
    final String[] names;
    final HashMap<String, Customer> map;
    long nextCustomerNo;

    Customers(Config config, Rnd random) {
      this.config = config;
      names = new String[config.numCustomers];
      map = new HashMap<>(config.numCustomers * 4 / 3);
      for (int i = 0; i < config.numCustomers; i++) {
        String name = randomDistinctName(random);
        names[i] = name;
        map.put(name, new Customer(name, nextCustomerNo++));
      }
    }

    static String capitalize(String s) { return Character.toUpperCase(s.charAt(0)) + s.substring(1); }

    String randomDistinctName(Rnd random) {
      while (true) {
        String first = capitalize(config.arbitraryWord(random));
        String last = capitalize(config.arbitraryWord(random));
        String fullName = first + " " + last;
        if (!map.containsKey(fullName)) return fullName;
      }
    }

    Customer selectRandomCustomer(Rnd random) { return map.get(names[random.nextInt(config.numCustomers)]); }

    void replaceRandomCustomer(Rnd random) {
      int index = random.nextInt(config.numCustomers);
      String newName = randomDistinctName(random);
      Customer obsolete = map.get(names[index]);
      obsolete.prepareForDemise();
      names[index] = newName;
      map.remove(obsolete.name);
      map.put(newName, new Customer(newName, nextCustomerNo++));
    }

    long purchaseHash() {
      long sum = 0;
      for (Customer c : map.values()) sum += c.purchaseHash;
      return sum;
    }
  }

  static final class Products {
    final Config config;
    final long[] productIds;
    final TreeMap<Long, Product> productMap = new TreeMap<>();
    final TreeMap<String, HashSet<Long>> nameIndex = new TreeMap<>();
    final TreeMap<String, HashSet<Long>> descriptionIndex = new TreeMap<>();
    long nextProductId;

    Products(Config config, Rnd random) {
      this.config = config;
      productIds = new long[config.numProducts];
      for (int i = 0; i < config.numProducts; i++) {
        Product p = newProduct(random);
        productIds[i] = p.id;
        productMap.put(p.id, p);
        addToIndices(p);
      }
    }

    Product newProduct(Rnd random) {
      String name = config.randomString(config.productNameLength, random);
      String description = config.randomString(config.productDescriptionLength, random);
      return new Product(nextProductId++, name, description);
    }

    static List<String> words(String s) {
      List<String> result = new ArrayList<>();
      int start = 0, size = s.length();
      while (start < size) {
        int stop = start;
        while (stop < size && s.charAt(stop) != ' ') stop++;
        result.add(s.substring(start, stop));
        start = stop;
        while (start < size && s.charAt(start) == ' ') start++;
      }
      return result;
    }

    void addToIndices(Product p) {
      for (String w : words(p.name)) nameIndex.computeIfAbsent(w, k -> new HashSet<>()).add(p.id);
      for (String w : words(p.description)) descriptionIndex.computeIfAbsent(w, k -> new HashSet<>()).add(p.id);
    }

    void removeFromIndices(Product p) {
      for (String w : words(p.name)) { HashSet<Long> s = nameIndex.get(w); if (s != null) s.remove(p.id); }
      for (String w : words(p.description)) { HashSet<Long> s = descriptionIndex.get(w); if (s != null) s.remove(p.id); }
    }

    void addMatches(String word, TreeMap<String, HashSet<Long>> index, HashSet<Product> set) {
      HashSet<Long> ids = index.get(word);
      if (ids == null) return;
      for (Long id : ids) {
        Product p = productMap.get(id);
        if (p != null && p.available) set.add(p);
      }
    }

    HashSet<Product> matchesOf(String word) {
      HashSet<Product> matches = new HashSet<>();
      addMatches(word, nameIndex, matches);
      addMatches(word, descriptionIndex, matches);
      return matches;
    }

    Product[] lookupProductsMatchingAll(String[] keywords) {
      HashSet<Product> intersection = matchesOf(keywords[0]);
      for (int i = 1; i < keywords.length; i++) {
        if (intersection.isEmpty()) return new Product[0];
        HashSet<Product> newMatches = matchesOf(keywords[i]);
        HashSet<Product> removeSet = new HashSet<>();
        for (Product p : intersection) if (!newMatches.contains(p)) removeSet.add(p);
        for (Product p : removeSet) intersection.remove(p);
      }
      return sortedById(intersection);
    }

    Product[] lookupProductsMatchingAny(String[] keywords) {
      HashSet<Product> accumulator = new HashSet<>();
      for (String k : keywords) {
        addMatches(k, nameIndex, accumulator);
        addMatches(k, descriptionIndex, accumulator);
      }
      return sortedById(accumulator);
    }

    static Product[] sortedById(HashSet<Product> set) {
      Product[] result = set.toArray(new Product[0]);
      Arrays.sort(result, (a, b) -> Long.compare(a.id, b.id));
      return result;
    }

    void replaceRandomProduct(Rnd random) {
      Product p = newProduct(random);
      int index = random.nextInt(productIds.length);
      Product removed = productMap.remove(productIds[index]);
      productIds[index] = p.id;
      removed.available = false;
      productMap.put(p.id, p);
      removeFromIndices(removed);
      addToIndices(p);
    }
  }

  static final class Tally {
    long sessions, candidates, noChoices, purchases, saves, abandons, sales, expirations, customerReplacements, productReplacements;
    public String toString() {
      return " sessions=" + sessions + " candidates=" + candidates + " noChoices=" + noChoices + " purchases=" + purchases
          + " saves=" + saves + " abandons=" + abandons + " sales=" + sales + " expirations=" + expirations
          + " customerReplacements=" + customerReplacements + " productReplacements=" + productReplacements;
    }
  }

  abstract static class Actor {
    final int id;
    long time;
    final Rnd random;
    final Config config;
    final Customers customers;
    final Products products;
    final BrowsingQueue browsingQueue;
    final SalesQueue salesQueue;
    Actor(int id, long time, Rnd random, Config config, Customers customers, Products products, BrowsingQueue bq, SalesQueue sq) {
      this.id = id; this.time = time; this.random = random; this.config = config; this.customers = customers;
      this.products = products; browsingQueue = bq; salesQueue = sq;
    }
    abstract int fire(Tally tally);
  }

  static final class CustomerActor extends Actor {
    long release;
    boolean deciding;
    Customer customer;
    SalesTransaction[] prospects;
    String[] selectors;

    CustomerActor(int id, long time, Rnd random, Config config, Customers customers, Products products, BrowsingQueue bq, SalesQueue sq) {
      super(id, time, random, config, customers, products, bq, sq);
      release = time;
    }

    int fire(Tally tally) {
      if (deciding) { decide(tally); return 1; }
      prepare(tally);
      return 0;
    }

    void prepare(Tally tally) {
      customer = customers.selectRandomCustomer(random);
      String[] keywords = config.randomKeywords(config.keywordSearchCount, random);
      Product[] all = products.lookupProductsMatchingAll(keywords);
      Product[] any = config.allowAnyMatch ? products.lookupProductsMatchingAny(keywords) : new Product[0];
      Product[] scrutinize = all.length > 0 ? all : any;
      Product[] saved = customer.allSavedForLater();
      Product[] candidates = scrutinize;
      if (saved.length > 0) {
        candidates = Arrays.copyOf(scrutinize, scrutinize.length + saved.length);
        System.arraycopy(saved, 0, candidates, scrutinize.length, saved.length);
      }
      tally.sessions++;
      tally.candidates += candidates.length;
      if (candidates.length == 0) {
        tally.noChoices++;
        customer = null;
        nextSession();
        return;
      }
      prospects = new SalesTransaction[candidates.length];
      for (int i = 0; i < candidates.length; i++)
        prospects[i] = new SalesTransaction(customer, candidates[i], config.randomString(config.productReviewLength, random));
      selectors = config.randomKeywords(config.selectionCriteriaCount, random);
      deciding = true;
      time = release + config.customerThinkTime;
    }

    void decide(Tally tally) {
      int best = 0;
      double bestMatch = rank(prospects[0]);
      for (int i = 1; i < prospects.length; i++) {
        double r = rank(prospects[i]);
        if (r > bestMatch) { bestMatch = r; best = i; }
      }
      SalesTransaction selected = prospects[best];
      prospects = null;
      selectors = null;
      double coin = random.nextFloat();
      if (coin < config.buyThreshold) {
        salesQueue.enqueue(selected);
        tally.purchases++;
      } else if (coin < config.saveForLaterThreshold + config.buyThreshold) {
        BrowsingHistory h = new BrowsingHistory(selected.customer, selected.product, time + config.browsingExpiration, browsingQueue);
        browsingQueue.enqueue(h);
        selected.customer.addSaveForLater(h);
        tally.saves++;
      } else {
        tally.abandons++;
      }
      customer = null;
      nextSession();
    }

    void nextSession() {
      deciding = false;
      release += config.customerPeriod;
      time = release;
    }

    double rank(SalesTransaction prospect) {
      String review = prospect.review;
      double ranking = 1.0;
      for (String criterion : selectors) ranking *= goodness(criterion, review);
      return ranking;
    }

    static double goodness(String keyword, String text) {
      double similarity = 1.0, scale = 0.9375, penalize = scale;
      for (int subLength = keyword.length(); subLength > 0; subLength--) {
        for (int start = 0; start + subLength <= keyword.length(); start++) {
          if (text.contains(keyword.substring(start, start + subLength))) return similarity;
          similarity *= penalize;
        }
        penalize *= scale;
      }
      return similarity;
    }
  }

  static final class ServerActor extends Actor {
    int attention;
    long customerReplacementTime, productReplacementTime;

    ServerActor(int id, long time, Rnd random, Config config, Customers customers, Products products, BrowsingQueue bq, SalesQueue sq,
                int attention, long crt, long prt) {
      super(id, time, random, config, customers, products, bq, sq);
      this.attention = attention;
      customerReplacementTime = crt;
      productReplacementTime = prt;
    }

    int fire(Tally tally) {
      switch (attention) {
        case 0: {
          SalesTransaction sale;
          while ((sale = salesQueue.dequeue()) != null) { sale.customer.transactSale(sale, time); tally.sales++; }
          break;
        }
        case 1: {
          BrowsingHistory h;
          while ((h = browsingQueue.pullIfExpired(time)) != null) { h.customer.retireOneSaveForLater(h); tally.expirations++; }
          break;
        }
        case 2:
          if (time >= customerReplacementTime) {
            for (int i = 0; i < config.customerReplacementCount; i++) { customers.replaceRandomCustomer(random); tally.customerReplacements++; }
            customerReplacementTime += config.customerReplacementPeriod;
          }
          break;
        case 3:
          if (time >= productReplacementTime) {
            for (int i = 0; i < config.productReplacementCount; i++) { products.replaceRandomProduct(random); tally.productReplacements++; }
            productReplacementTime += config.productReplacementPeriod;
          }
          break;
      }
      attention = attention == 0 ? 3 : attention - 1;
      time += config.serverPeriod;
      return 2;
    }
  }

  static final class Latencies {
    final String name;
    long[] samples = new long[1024];
    int count;
    Latencies(String name) { this.name = name; }
    void add(long us) {
      if (count == samples.length) samples = Arrays.copyOf(samples, count * 2);
      samples[count++] = us;
    }
    void report() {
      if (count == 0) { System.out.println("# latency " + name + " 0"); return; }
      long[] sorted = Arrays.copyOf(samples, count);
      Arrays.sort(sorted);
      long sum = 0;
      for (long s : sorted) sum += s;
      StringBuilder out = new StringBuilder("# latency " + name + " " + count + " " + sum / count);
      long[][] q = {{500, 1000}, {900, 1000}, {990, 1000}, {999, 1000}, {9999, 10000}};
      for (long[] kn : q) out.append(' ').append(sorted[(int) Math.max(1, (count * kn[0] + kn[1] - 1) / kn[1]) - 1]);
      out.append(' ').append(sorted[count - 1]);
      System.out.println(out);
    }
  }

  static long micros() { return System.nanoTime() / 1000; }

  Config config = new Config();
  Customers customers;
  Products products;
  PriorityQueue<Actor> scheduler;
  Tally tally = new Tally();
  Latencies[] latencies = {new Latencies("preparation"), new Latencies("decision"), new Latencies("server")};

  void setUp() {
    Rnd seeder = new Rnd(config.randomSeed, 16807);
    config.makeWords(new Rnd(seeder.next()));
    Rnd random = new Rnd(seeder.next());
    products = new Products(config, random);
    customers = new Customers(config, random);
    BrowsingQueue[] bqs = new BrowsingQueue[config.browsingHistoryQueueCount];
    for (int i = 0; i < bqs.length; i++) bqs[i] = new BrowsingQueue();
    SalesQueue[] sqs = new SalesQueue[config.salesTransactionQueueCount];
    for (int i = 0; i < sqs.length; i++) sqs[i] = new SalesQueue();
    scheduler = new PriorityQueue<>((a, b) -> a.time != b.time ? Long.compare(a.time, b.time) : Integer.compare(a.id, b.id));
    long customerStagger = config.customerPeriod / config.customerThreads;
    int bq = bqs.length - 1, sq = sqs.length - 1;
    for (int i = 1; i <= config.customerThreads; i++) {
      scheduler.add(new CustomerActor(i, (i - 1) * customerStagger, new Rnd(seeder.next()), config, customers, products, bqs[bq], sqs[sq]));
      bq = bq == 0 ? bqs.length - 1 : bq - 1;
      sq = sq == 0 ? sqs.length - 1 : sq - 1;
    }
    long serverStagger = config.serverPeriod / config.serverThreads;
    bq = bqs.length - 1;
    sq = sqs.length - 1;
    for (int i = 1; i <= config.serverThreads; i++) {
      scheduler.add(new ServerActor(config.customerThreads + i, (i - 1) * serverStagger, new Rnd(seeder.next()), config, customers, products,
          bqs[bq], sqs[sq], (i - 1) % 4,
          (i - 1) * (config.customerReplacementPeriod / config.serverThreads),
          (i - 1) * (config.productReplacementPeriod / config.serverThreads)));
      bq = bq == 0 ? bqs.length - 1 : bq - 1;
      sq = sq == 0 ? sqs.length - 1 : sq - 1;
    }
  }

  void simulate() {
    long minute = 60_000_000L, end = config.simulationMinutes * minute, warmupEnd = config.warmupMinutes * minute;
    long mark = minute, lap = micros();
    boolean measuring = false;
    while (!scheduler.isEmpty() && scheduler.peek().time < end) {
      Actor actor = scheduler.poll();
      long eventTime = actor.time;
      if (!measuring && eventTime >= warmupEnd) {
        // GC pauses come from -Xlog:safepoint: the measured minutes in the log's uptime.
        System.out.println("# measured from uptime_ms=" + ManagementFactory.getRuntimeMXBean().getUptime());
        measuring = true;
      }
      while (eventTime >= mark) {
        long t0 = micros();
        System.out.println("Extremem," + mark / minute + "," + (t0 - lap));
        lap = t0;
        mark += minute;
      }
      long t0 = micros();
      int kind = actor.fire(tally);
      long t1 = micros();
      if (eventTime >= warmupEnd) latencies[kind].add(t1 - t0);
      scheduler.add(actor);
    }
    System.out.println("Extremem," + mark / minute + "," + (micros() - lap));
    System.out.println("# measured until uptime_ms=" + ManagementFactory.getRuntimeMXBean().getUptime());
  }

  static String gcStats() {
    // Pauses apart from concurrent cycles (ZGC's and Shenandoah's "... Cycles", "G1 Concurrent GC").
    long count = 0, ms = 0, cycles = 0, cycleMs = 0;
    for (GarbageCollectorMXBean gc : ManagementFactory.getGarbageCollectorMXBeans()) {
      if (gc.getName().contains("Cycles") || gc.getName().contains("Concurrent")) {
        cycles += Math.max(0, gc.getCollectionCount());
        cycleMs += Math.max(0, gc.getCollectionTime());
      } else {
        count += Math.max(0, gc.getCollectionCount());
        ms += Math.max(0, gc.getCollectionTime());
      }
    }
    long allocated = ((com.sun.management.ThreadMXBean) ManagementFactory.getThreadMXBean()).getCurrentThreadAllocatedBytes();
    return " gcs=" + count + " gcMilliseconds=" + ms + " concurrentCycles=" + cycles + " concurrentMilliseconds=" + cycleMs
        + " bytesAllocated=" + allocated;
  }

  public static void main(String[] args) throws Exception {
    Extremem x = new Extremem();
    for (String arg : args) {
      int i = arg.indexOf('=');
      x.config.set(arg.substring(0, i), arg.substring(i + 1));
    }
    long start = micros();
    x.setUp();
    System.out.println("# setup " + (micros() - start) + " us");
    start = micros();
    x.simulate();
    System.out.println("# simulation " + (micros() - start) + " us");
    for (Latencies l : x.latencies) l.report();
    System.out.println("# tally" + x.tally + " purchaseHash=" + x.customers.purchaseHash());
    System.out.println("# stats Extremem" + gcStats());
  }
}
