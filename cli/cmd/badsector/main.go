package main

import (
	"fmt"
	"os"

	"github.com/spf13/cobra"
)

var apiURL string

func main() {
	root := &cobra.Command{
		Use:   "badsector",
		Short: "BadSector CLI — manage your edge security platform",
	}

	root.PersistentFlags().StringVar(&apiURL, "api", "http://localhost:8080", "BadSector API URL")

	root.AddCommand(sitesCmd())
	root.AddCommand(reloadCmd())
	root.AddCommand(pluginCmd())

	if err := root.Execute(); err != nil {
		os.Exit(1)
	}
}

func sitesCmd() *cobra.Command {
	cmd := &cobra.Command{
		Use:   "sites",
		Short: "Manage sites",
	}
	cmd.AddCommand(&cobra.Command{
		Use:   "list",
		Short: "List all sites",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("Fetching sites from %s/api/v1/sites\n", apiURL)
			// HTTP client implementation in future PR
		},
	})
	return cmd
}

func reloadCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "reload",
		Short: "Trigger runtime config reload",
		Run: func(cmd *cobra.Command, args []string) {
			fmt.Printf("POST %s/api/v1/runtime/reload\n", apiURL)
		},
	}
}

func pluginCmd() *cobra.Command {
	return &cobra.Command{
		Use:   "plugin",
		Short: "Manage Lua plugins",
	}
}
