/* CLBG binary-trees, depth 17, its long-lived tree 20 deep: as BinaryTrees (RealWorld.st). Nodes from malloc, freed after their check.
   -DMAX_DEPTH=21 -DEXPECTED=611669342: the benchmarks game's size. */
#define NAME "BinaryTrees"
#ifndef MAX_DEPTH
#define MAX_DEPTH 17
#define EXPECTED 31806814
#endif
#include "harness.h"

typedef struct Node { struct Node *left, *right; } Node;

static Node *bottom_up(int depth)
{
    Node *n = malloc(sizeof(Node));
    if (depth == 0) {
        n->left = n->right = NULL;
    } else {
        n->left = bottom_up(depth - 1);
        n->right = bottom_up(depth - 1);
    }
    return n;
}

static int64_t check(const Node *n)
{
    if (n->left == NULL) return 1;
    return 1 + check(n->left) + check(n->right);
}

static void release(Node *n)
{
    if (n->left != NULL) {
        release(n->left);
        release(n->right);
    }
    free(n);
}

static int64_t setup(void) { return 0; }

static int64_t run(void)
{
    const int max_depth = MAX_DEPTH, live_depth = 20;
    Node *stretch = bottom_up(max_depth + 1);
    int64_t total = check(stretch);
    release(stretch);
    Node *long_lived = bottom_up(live_depth);
    for (int depth = 4; depth <= max_depth; depth += 2) {
        int64_t count = (int64_t)1 << (max_depth - depth + 4);
        for (int64_t i = 1; i <= count; i++) {
            Node *t = bottom_up(depth);
            total += check(t);
            release(t);
        }
    }
    total += check(long_lived);
    release(long_lived);
    return total;
}
