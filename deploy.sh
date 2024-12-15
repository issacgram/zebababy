#!/bin/bash

# Colors and styling
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'
BOLD='\033[1m'

# Help message
show_help() {
   echo "Usage: ./deploy.sh [OPTIONS]"
   echo "Options:"
   echo "  --step=STEPNAME    Run only specified step"
   echo "  --finish          Continue with remaining steps after specified step"
   echo "  --help            Show this help message"
   echo ""
   echo "Available steps:"
   echo "  init"
   echo "  pull_changes"
   echo "  install_dependencies" 
   echo "  run_migrations"
   echo "  cache_config"
   echo "  restart_services"
}

# Execute command with status check
execute_step() {
   local description=$1
   local icon=$2
   local command=$3
   local step_name=$4
   
   # Check if step is enabled in YAML
   local status=$(grep -A4 "    ${step_name}:" deploy.yml | grep 'status:' | sed 's/.*status: *\(.*\)/\1/')
   if [ "$status" = "false" ]; then
       echo -e "${YELLOW}${icon} ${BOLD}${description} (Skipped - disabled in config)${NC}"
       return 0
   fi
   
   printf "${BLUE}${icon} ${BOLD}${description}...${NC}"
   output=$(eval "$command" 2>&1)
   status=$?
   if [ $status -eq 0 ]; then
       printf "${GREEN}✓${NC}\n"
   else
       printf "\n${RED}✗ Failed${NC}\n"
       printf "${RED}Error output:${NC}\n$output\n"
       exit 1
   fi
}

# Execute specific step
run_step() {
   local step=$1
   local description=$(grep -A4 "    ${step}:" deploy.yml | grep 'description:' | sed 's/.*description: *"\(.*\)".*/\1/')
   local icon=$(grep -A4 "    ${step}:" deploy.yml | grep 'icon:' | sed 's/.*icon: *"\(.*\)".*/\1/')
   local command=$(grep -A4 "    ${step}:" deploy.yml | grep 'command:' | sed 's/.*command: *"\(.*\)".*/\1/')
   
   if [ -n "$description" ] && [ -n "$command" ]; then
       execute_step "$description" "$icon" "ssh ${USERNAME}@${HOST} 'cd ${PATH_DEPLOY} && $command'" "$step"
       return 0
   fi
   return 1
}

# Main deployment logic
main() {
   # Parse command line arguments
   SINGLE_STEP=""
   FINISH_AFTER=false
   
   for arg in "$@"; do
       case $arg in
           --step=*)
           SINGLE_STEP="${arg#*=}"
           ;;
           --finish)
           FINISH_AFTER=true
           ;;
           --help)
           show_help
           exit 0
           ;;
       esac
   done
   
   echo -e "${YELLOW}🚀 Starting deployment${NC}\n"
   
   # Load configuration
   HOST=$(grep 'host:' deploy.yml | awk '{print $2}' | tr -d '"')
   USERNAME=$(grep 'username:' deploy.yml | awk '{print $2}' | tr -d '"')
   PATH_DEPLOY=$(grep 'path:' deploy.yml | awk '{print $2}' | tr -d '"')
   BRANCH=$(grep 'branch:' deploy.yml | awk '{print $2}' | tr -d '"')
   REPO=$(grep 'repo:' deploy.yml | awk '{print $2}' | tr -d '"')
   
   # Debug: Print configuration
   echo "Configuration:"
   echo "Host: ${HOST}"
   echo "User: ${USERNAME}"
   echo "Path: ${PATH_DEPLOY}"
   echo "Branch: ${BRANCH}"
   echo "Repository: ${REPO}"
   echo "-------------------"
   
   # Check SSH connection
   if ! ssh -q -o BatchMode=yes -o ConnectTimeout=5 "${USERNAME}@${HOST}" 'exit' 2>/dev/null; then
       echo -e "${RED}✗ Cannot connect to server${NC}"
       exit 1
   fi
   
   # Run initialization steps if needed
   if [ -z "$SINGLE_STEP" ] || [ "$SINGLE_STEP" = "init" ]; then
       execute_step "Creating directory" "📁" "ssh ${USERNAME}@${HOST} 'mkdir -p ${PATH_DEPLOY}'" "directory"
       execute_step "Initializing repository" "🌱" "ssh ${USERNAME}@${HOST} '[ -d ${PATH_DEPLOY}/.git ] || git clone ${REPO} ${PATH_DEPLOY}'" "init"
   fi
   
   # Handle single step or full deployment
   if [ -n "$SINGLE_STEP" ]; then
       if ! run_step "$SINGLE_STEP"; then
           echo -e "${RED}✗ Step '$SINGLE_STEP' not found${NC}"
           show_help
           exit 1
       fi
       
       if [ "$FINISH_AFTER" = "true" ]; then
           local steps="pull_changes install_dependencies run_migrations cache_config restart_services"
           local found=false
           
           for step in $steps; do
               if [ "$step" = "$SINGLE_STEP" ]; then
                   found=true
                   continue
               fi
               if [ "$found" = "true" ]; then
                   run_step "$step"
               fi
           done
       fi
   else
       for step in pull_changes install_dependencies run_migrations cache_config restart_services; do
           run_step "$step"
       done
   fi
   
   echo -e "\n${GREEN}✨ Deployment completed successfully!${NC}"
}

# Run deployment
main "$@"