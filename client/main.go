package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"sort"
	"sync"
	"sync/atomic"
	"time"

	pb "github.com/hj24/grpc-lb-test/protogen/echo"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
)

type Stats struct {
	mu      sync.Mutex
	podDist map[string]int64
	total   int64
}

func (s *Stats) Record(podKey string) {
	s.mu.Lock()
	defer s.mu.Unlock()
	if s.podDist == nil {
		s.podDist = make(map[string]int64)
	}
	s.podDist[podKey]++
}

func (s *Stats) Print() {
	s.mu.Lock()
	defer s.mu.Unlock()

	if len(s.podDist) == 0 {
		fmt.Println("\nNo responses received")
		return
	}

	fmt.Println("\n=== Pod Distribution ===")

	// Sort by count (descending)
	type kv struct {
		Key   string
		Count int64
	}
	var sorted []kv
	for k, v := range s.podDist {
		sorted = append(sorted, kv{k, v})
	}
	sort.Slice(sorted, func(i, j int) bool {
		return sorted[i].Count > sorted[j].Count
	})

	total := int64(0)
	for _, item := range sorted {
		total += item.Count
	}

	for _, item := range sorted {
		pct := float64(item.Count) / float64(total) * 100
		fmt.Printf("  %6d (%.1f%%) - %s\n", item.Count, pct, item.Key)
	}
	fmt.Printf("\nTotal requests: %d\n", total)
	fmt.Printf("Unique pods:    %d\n", len(sorted))
}

func main() {
	target := flag.String("target", "grpc-server.test.svc.cluster.local:9000", "gRPC server target")
	total := flag.Int("total", 1000, "total number of requests")
	concurrency := flag.Int("concurrency", 50, "concurrent workers")
	conns := flag.Int("conns", 3, "number of gRPC connections")
	timeout := flag.Duration("timeout", 10*time.Second, "request timeout")
	loop := flag.Bool("loop", false, "run in loop mode")
	interval := flag.Duration("interval", 10*time.Second, "interval between loops (in loop mode)")
	verbose := flag.Bool("verbose", false, "verbose output (print each response)")
	flag.Parse()

	log.Printf("gRPC Load Test Client")
	log.Printf("  Target:       %s", *target)
	log.Printf("  Total:        %d", *total)
	log.Printf("  Concurrency:  %d", *concurrency)
	log.Printf("  Connections:  %d", *conns)
	log.Printf("  Timeout:      %v", *timeout)
	log.Printf("  Loop:         %v", *loop)
	if *loop {
		log.Printf("  Interval:     %v", *interval)
	}
	log.Printf("  Verbose:      %v", *verbose)

	// Create connections
	log.Printf("\nEstablishing %d connection(s)...", *conns)
	var connections []*grpc.ClientConn
	for i := 0; i < *conns; i++ {
		conn, err := grpc.Dial(*target,
			grpc.WithTransportCredentials(insecure.NewCredentials()),
			grpc.WithBlock(),
			grpc.WithTimeout(10*time.Second))
		if err != nil {
			log.Fatalf("Failed to connect: %v", err)
		}
		connections = append(connections, conn)
		defer conn.Close()
	}
	log.Printf("Connected!")

	runTest := func() {
		stats := &Stats{}
		var completedReqs int64
		var errors int64

		start := time.Now()

		// Worker pool
		var wg sync.WaitGroup
		reqChan := make(chan int, *total)

		for w := 0; w < *concurrency; w++ {
			wg.Add(1)
			go func(workerID int) {
				defer wg.Done()

				// Round-robin connection selection
				conn := connections[workerID%len(connections)]
				client := pb.NewEchoClient(conn)

				for range reqChan {
					ctx, cancel := context.WithTimeout(context.Background(), *timeout)

					resp, err := client.Echo(ctx, &pb.EchoRequest{
						Message: fmt.Sprintf("test-%d", workerID),
					})
					cancel()

					if err != nil {
						atomic.AddInt64(&errors, 1)
						if *verbose {
							log.Printf("Error: %v", err)
						}
						continue
					}

					atomic.AddInt64(&completedReqs, 1)

					// Create pod key
					podKey := fmt.Sprintf("%s (%s)", resp.PodName, resp.PodIp)
					if resp.Hostname != "" && resp.Hostname != resp.PodName {
						podKey = fmt.Sprintf("%s / %s (%s)", resp.PodName, resp.Hostname, resp.PodIp)
					}

					stats.Record(podKey)

					if *verbose {
						fmt.Printf("Response: %s | %s\n", resp.Message, podKey)
					}
				}
			}(w)
		}

		// Send requests
		for i := 0; i < *total; i++ {
			reqChan <- i
		}
		close(reqChan)

		// Wait for completion
		wg.Wait()
		duration := time.Since(start)

		// Print statistics
		fmt.Println("\n" + repeatStr("=", 50))
		log.Printf("Test completed in %v", duration)
		log.Printf("Successful: %d", atomic.LoadInt64(&completedReqs))
		log.Printf("Errors:     %d", atomic.LoadInt64(&errors))
		log.Printf("RPS:        %.2f", float64(*total)/duration.Seconds())

		stats.Print()
		fmt.Println(repeatStr("=", 50))
	}

	if *loop {
		log.Println("\nRunning in loop mode (Ctrl+C to stop)...")
		for {
			runTest()
			log.Printf("\nWaiting %v before next run...\n", *interval)
			time.Sleep(*interval)
		}
	} else {
		log.Println("\nStarting test...")
		runTest()
	}
}

// Helper to repeat strings
func repeatStr(s string, count int) string {
	result := ""
	for i := 0; i < count; i++ {
		result += s
	}
	return result
}
