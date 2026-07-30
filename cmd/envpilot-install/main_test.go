package main

import "testing"

func TestValidateFrontendAccess(t *testing.T) {
	tests := []struct {
		name string
		cfg  config
		want bool
	}{
		{name: "ingress", cfg: config{FrontendAccessMode: "ingress"}, want: true},
		{name: "allocated nodeport", cfg: config{FrontendAccessMode: "nodeport"}, want: true},
		{name: "fixed nodeport", cfg: config{FrontendAccessMode: "nodeport", FrontendNodePort: 31080}, want: true},
		{name: "nodeport in ingress mode", cfg: config{FrontendAccessMode: "ingress", FrontendNodePort: 31080}},
		{name: "out of range nodeport", cfg: config{FrontendAccessMode: "nodeport", FrontendNodePort: 28080}},
		{name: "unknown mode", cfg: config{FrontendAccessMode: "loadbalancer"}},
	}
	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			err := validateFrontendAccess(tt.cfg)
			if (err == nil) != tt.want {
				t.Fatalf("validateFrontendAccess(%+v) error = %v, want success=%t", tt.cfg, err, tt.want)
			}
		})
	}
}
