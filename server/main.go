package main

import (
	"context"
	"flag"
	"fmt"
	"log"
	"net"
	"os"

	pb "github.com/hj24/grpc-lb-test/protogen/echo"
	"google.golang.org/grpc"
	"google.golang.org/grpc/reflection"
)

type echoServer struct {
	pb.UnimplementedEchoServer
	hostname string
	podName  string
	podIP    string
}

func (s *echoServer) Echo(ctx context.Context, req *pb.EchoRequest) (*pb.EchoResponse, error) {
	return &pb.EchoResponse{
		Message:  req.Message,
		Hostname: s.hostname,
		PodName:  s.podName,
		PodIp:    s.podIP,
	}, nil
}

func main() {
	port := flag.Int("port", 9000, "gRPC server port")
	flag.Parse()

	// Get hostname
	hostname, err := os.Hostname()
	if err != nil {
		log.Printf("Warning: failed to get hostname: %v", err)
		hostname = "unknown"
	}

	// Get pod info from environment (Downward API)
	podName := os.Getenv("POD_NAME")
	if podName == "" {
		podName = hostname
	}

	podIP := os.Getenv("POD_IP")
	if podIP == "" {
		podIP = "unknown"
	}

	log.Printf("Starting gRPC server...")
	log.Printf("  Hostname: %s", hostname)
	log.Printf("  Pod Name: %s", podName)
	log.Printf("  Pod IP:   %s", podIP)
	log.Printf("  Port:     %d", *port)

	lis, err := net.Listen("tcp", fmt.Sprintf(":%d", *port))
	if err != nil {
		log.Fatalf("Failed to listen: %v", err)
	}

	s := grpc.NewServer()
	pb.RegisterEchoServer(s, &echoServer{
		hostname: hostname,
		podName:  podName,
		podIP:    podIP,
	})

	// Register reflection service for debugging
	reflection.Register(s)

	log.Printf("Server listening on :%d", *port)
	if err := s.Serve(lis); err != nil {
		log.Fatalf("Failed to serve: %v", err)
	}
}
