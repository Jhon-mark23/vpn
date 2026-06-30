#git add . && git commit -m "update" && git push
#!/bin/bash
# ============================================================
# Git Auto Push with Random Creative Messages
# ============================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Fun creative messages
MESSAGES=(
    "🚀 launching into orbit"
    "✨ sprinkling magic dust"
    "🔥 dropping hot fixes"
    "🛠️ fixing what ain't broken"
    "📦 shipping new goodies"
    "🔧 tuning the engine"
    "⚡ boosting performance"
    "🐛 squashing bugs"
    "🧹 cleaning up the mess"
    "💪 making it stronger"
    "🎯 hitting the mark"
    "📈 pushing the limits"
    "🌈 adding some color"
    "🎵 making it sing"
    "⚡ charging forward"
    "🌟 polishing the diamond"
    "🔨 hammering out features"
    "🧪 testing in production"
    "🤞 hoping it works"
    "🚂 chugging along"
    "🎮 leveling up"
    "📝 documenting the chaos"
    "🧩 putting pieces together"
    "🎨 painting the town red"
    "🏗️ building the future"
)

generate_random_message() {
    echo "${MESSAGES[$((RANDOM % ${#MESSAGES[@]}))]}"
}

git_push() {
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}📦 Git Auto Push${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        echo -e "${RED}✗ Not a git repository!${NC}"
        exit 1
    fi
    
    local branch=$(git branch --show-current)
    echo -e "${YELLOW}📍 Branch:${NC} $branch"
    
    if git diff --quiet && git diff --cached --quiet; then
        echo -e "${RED}✗ No changes!${NC}"
        exit 0
    fi
    
    local msg=$(generate_random_message)
    echo -e "${YELLOW}📝 Commit:${NC} \"$msg\""
    
    git add .
    git commit -m "$msg"
    
    if git push origin $branch; then
        echo -e "${GREEN}✅ Done!${NC}"
    else
        echo -e "${RED}❌ Failed!${NC}"
        exit 1
    fi
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

git_push
