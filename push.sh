#!/bin/bash
# ============================================================
# Git Auto Push with Random IT Dev Jokes
# ============================================================
clear
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# IT Developer Jokes Collection
JOKES=(
    # Classic IT Jokes
    "Why do programmers prefer dark mode? Because light attracts bugs! 🐛"
    "There are 10 types of people - those who understand binary and those who don't! 👾"
    "My code works... I don't know why! 💻"
    "It's not a bug, it's an undocumented feature! ✨"
    "I'm not lazy, I'm just in energy-saving mode! ⚡"
    "Java developers wear glasses because they can't C#! 👓"
    "Why did the developer go broke? Because he used up all his cache! 💰"
    "SQL injection - When you drop the table, you also drop the mic! 🎤"
    "I have a TCP joke for you, but I'm afraid you won't get it! 📡"
    "Why did the JavaScript developer wear glasses? Because he couldn't C#! 🤓"
    "Debugging is like being the detective in a crime movie where you're also the murderer! 🔍"
    "Why do Java developers have to wear glasses? Because they can't C#! 😎"
    "My code's so clean, it's practically sterile! 🧼"
    "I'm 99.9% sure my code works... I'll test it in production! 🎲"
    "What's the object-oriented way to become wealthy? Inheritance! 💰"
    "I don't always test my code, but when I do, I do it in production! 🚀"
    
    # Programming Life
    "There are 2 hard problems in CS: cache invalidation, naming things, and off-by-1 errors! 🔢"
    "Why do programmers always mix up Halloween and Christmas? Oct 31 == Dec 25! 🎃"
    "What's a programmer's favorite hangout? The Foo Bar! 🍺"
    "A SQL query goes into a bar, walks up to two tables and asks: 'Can I join you?' 🍻"
    "How many programmers does it take to change a lightbulb? None, that's a hardware problem! 💡"
    "I'm not a robot, I'm just really good at CAPTCHA! 🤖"
    "My code is like my coffee - black and strong! ☕"
    "I'm not procrastinating, I'm just buffering! ⏳"
    "404: Sense of humor not found! 😂"
    "Pushed 1000 lines of code - 999 of them are comments! 📝"
    "I speak fluent Binary, Regex, and Sarcasm! 💬"
    "I'm not arguing, I'm just explaining why I'm right! 🧠"
    
    # Workplace Humor
    "Monday: Plan the week. Tuesday: Fix Monday's bugs. Wednesday: Fix Tuesday's fixes! 🔧"
    "My code works... on my machine! 💻"
    "Working as intended (he says while debugging) 🐛"
    "I'm not a control freak, but I know a better way to do everything! 🎯"
    "I didn't choose the dev life, the dev life chose me! 👨‍💻"
    "Commit early, commit often, commit before the coffee wears off! ☕"
    "I code, therefore I am (sometimes wrong)! 🧪"
    "Trust me, I'm an engineer... I have a degree in Google! 🔍"
    "What's a software developer's favorite music genre? Python! 🎵"
    "I'm not a magician, but I can make bugs disappear! 🎩"
    "My code is running... I'm in danger! ⚠️"
    "Coffee, Code, Repeat! 🔄"
    
    # Git/Version Control
    "git push --force: because sometimes you gotta break things! 💪"
    "git commit -m 'I have no idea what I'm doing' 🤷"
    "git stash: because I'm not ready for this! 🙈"
    "Merge conflict? More like merge therapy! 🧘"
    "git blame: I know it was you! 👀"
    "git push -f: applying a little bit of pressure! 💨"
)

generate_random_joke() {
    echo "${JOKES[$((RANDOM % ${#JOKES[@]}))]}"
}

git_push() {
    echo -e "${BLUE}╔══════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${PURPLE}          🚀 GIT AUTO PUSH - COMMIT WITH HUMOR          ${BLUE}║${NC}"
    echo -e "${BLUE}╚══════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Check if git repo
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}✗ Not a git repository!${NC}"
        exit 1
    fi
    
    # Get current branch
    local branch=$(git branch --show-current)
    echo -e "${CYAN}📍 Current Branch:${NC} ${YELLOW}$branch${NC}"
    
    # Check for changes
    if git diff --quiet && git diff --cached --quiet; then
        echo -e "${RED}✗ No changes to commit!${NC}"
        exit 0
    fi
    
    # Generate random joke
    local joke=$(generate_random_joke)
    echo -e "${CYAN}📝 Commit Message:${NC}"
    echo -e "${GREEN}\"$joke\"${NC}"
    echo ""
    
    # Show files being committed
    echo -e "${CYAN}📁 Files changed:${NC}"
    git status --short
    
    echo ""
  #  read -p "Proceed with commit? (y/N): " -n 1 -r
  #  echo
  #  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
  #      echo -e "${YELLOW}Aborted.${NC}"
  #      exit 0
  #  fi
    
    # Stage and commit
    echo -e "${YELLOW}⏳ Staging changes...${NC}"
    git add .
    
    echo -e "${YELLOW}⏳ Committing...${NC}"
    git commit -m "$joke"
    
    echo -e "${YELLOW}⏳ Pushing to origin/$branch...${NC}"
    if git push origin $branch; then
        echo ""
        echo -e "${GREEN}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${GREEN}║${PURPLE}           ✅ SUCCESSFULLY PUSHED WITH HUMOR!            ${GREEN}║${NC}"
        echo -e "${GREEN}╚══════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${CYAN}💬 \"$joke\"${NC}"
        echo ""
        
        # Show commit hash
        local commit_hash=$(git rev-parse --short HEAD)
        echo -e "${YELLOW}🔑 Commit:${NC} $commit_hash"
    else
        echo ""
        echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║${YELLOW}              ❌ PUSH FAILED! TRY AGAIN               ${RED}║${NC}"
        echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
        exit 1
    fi
}

# Check if it's a git repo first
git_push